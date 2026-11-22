//
//  ECDeviceGeneric.cpp
//  SMCSuperIO
//
//  Copyright © 2021 vit9696. All rights reserved.
//

#include "ECDeviceGeneric.hpp"
#include "SMCSuperIO.hpp"
#include <i386/proc_reg.h>
#include <IOKit/IOMessage.h>
#include <IOKit/acpi/IOACPITypes.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <libkern/c++/OSData.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSArray.h>
#include <libkern/c++/OSIterator.h>

namespace EC {

	static uint8_t sClevoBrightness = 0;
	static uint8_t sClevoLastNonZeroBrightness = 255;
	static bool sClevoOn = false;
	static size_t sClevoColorIdx = 4; // Cyan (index 4)
	static const uint32_t sPresetColors[] = {
		0x00FF0000, // Red
		0x00FFA500, // Orange
		0x00FFFF00, // Yellow
		0x0000FF00, // Green
		0x0000FFFF, // Cyan
		0x000000FF, // Blue
		0x00800080, // Purple
		0x00FF69B4, // Pink
		0x00FFFFFF  // White
	};
	static constexpr size_t sNumPresetColors = sizeof(sPresetColors) / sizeof(sPresetColors[0]);

	class ClevoBrightnessKey;
	class ClevoColorKey;
	class ClevoModeKey;

	static ClevoBrightnessKey *sValBrightness = nullptr;
	static ClevoColorKey *sValColor[3] = { nullptr, nullptr, nullptr };
	static ClevoModeKey *sValMode = nullptr;

	static _Atomic(bool) sDirtyBrightness = false;
	static _Atomic(uint8_t) sPendingBrightness = 0;
	static _Atomic(bool) sDirtyMode = false;
	static _Atomic(uint8_t) sPendingMode = 0;
	static _Atomic(bool) sDirtyColor[3] = {};
	static _Atomic(uint32_t) sPendingColor[3] = {};

	class ClevoBrightnessLKSBKey : public VirtualSMCValue {
	protected:
		SMC_RESULT update(const SMC_DATA *src) override {
			VirtualSMCValue::update(src);
			atomic_store_explicit(&sPendingBrightness, src[0], memory_order_relaxed);
			atomic_store_explicit(&sDirtyBrightness, true, memory_order_release);
			return SmcSuccess;
		}
	};

	class ClevoBrightnessKey : public VirtualSMCValue {
	public:
		void setSilent(uint8_t val) {
			VirtualSMCValue::update(reinterpret_cast<const SMC_DATA *>(&val));
		}
	protected:
		SMC_RESULT update(const SMC_DATA *src) override {
			VirtualSMCValue::update(src);
			atomic_store_explicit(&sPendingBrightness, src[0], memory_order_relaxed);
			atomic_store_explicit(&sDirtyBrightness, true, memory_order_release);
			return SmcSuccess;
		}
	};

	class ClevoColorKey : public VirtualSMCValue {
		uint8_t zone;
	public:
		ClevoColorKey(uint8_t z) : zone(z) {}
		void setSilent(uint32_t col) {
			uint8_t be[4] = {
				0x00,
				static_cast<uint8_t>((col >> 16) & 0xFF),
				static_cast<uint8_t>((col >> 8) & 0xFF),
				static_cast<uint8_t>(col & 0xFF)
			};
			VirtualSMCValue::update(reinterpret_cast<const SMC_DATA *>(be));
		}
	protected:
		SMC_RESULT update(const SMC_DATA *src) override {
			VirtualSMCValue::update(src);
			uint32_t col = (static_cast<uint32_t>(src[0]) << 24) | (static_cast<uint32_t>(src[1]) << 16) | (static_cast<uint32_t>(src[2]) << 8) | static_cast<uint32_t>(src[3]);
			if (zone < 3) {
				atomic_store_explicit(&sPendingColor[zone], col, memory_order_relaxed);
				atomic_store_explicit(&sDirtyColor[zone], true, memory_order_release);
			}
			return SmcSuccess;
		}
	};

	class ClevoModeKey : public VirtualSMCValue {
	public:
		void setSilent(uint8_t val) {
			VirtualSMCValue::update(reinterpret_cast<const SMC_DATA *>(&val));
		}
	protected:
		SMC_RESULT update(const SMC_DATA *src) override {
			VirtualSMCValue::update(src);
			atomic_store_explicit(&sPendingMode, src[0], memory_order_relaxed);
			atomic_store_explicit(&sDirtyMode, true, memory_order_release);
			return SmcSuccess;
		}
	};

	static IOACPIPlatformDevice *getDCHU() {
		static IOACPIPlatformDevice *cachedDCHU = nullptr;
		if (cachedDCHU) return cachedDCHU;

		auto dict = IOService::nameMatching("CLV0001");
		if (!dict) return nullptr;

		auto iter = IOService::getMatchingServices(dict);
		dict->release();
		if (iter) {
			cachedDCHU = OSDynamicCast(IOACPIPlatformDevice, iter->getNextObject());
			if (cachedDCHU) cachedDCHU->retain();
			iter->release();
		}
		return cachedDCHU;
	}

	static bool callClevoDCHU(uint8_t cmd, uint32_t arg, uint32_t *outVal = nullptr) {
		auto dchu = getDCHU();
		if (!dchu) return false;

		static const uint8_t clevo_uuid[16] = {
			0xe4, 0x24, 0xf2, 0x93, 0xdc, 0xfb, 0xbf, 0x4b,
			0xad, 0xd6, 0xdb, 0x71, 0xbd, 0xc0, 0xaf, 0xad
		};

		auto uuidData = OSData::withBytes(clevo_uuid, sizeof(clevo_uuid));
		auto revNum   = OSNumber::withNumber(static_cast<uint64_t>(0), 32);
		auto funcNum  = OSNumber::withNumber(static_cast<uint64_t>(cmd), 32);
		auto argNum   = OSNumber::withNumber(static_cast<uint64_t>(arg), 32);
		auto pkgArray = OSArray::withCapacity(1);

		if (uuidData && revNum && funcNum && argNum && pkgArray) {
			pkgArray->setObject(argNum);
			OSObject *params[4] = { uuidData, revNum, funcNum, pkgArray };
			OSObject *result = nullptr;
			dchu->evaluateObject("_DSM", &result, params, 4);
			if (result) {
				if (outVal) {
					if (auto num = OSDynamicCast(OSNumber, result)) {
						*outVal = num->unsigned32BitValue();
					} else if (auto data = OSDynamicCast(OSData, result)) {
						if (data->getLength() >= 4) {
							*outVal = *reinterpret_cast<const uint32_t *>(data->getBytesNoCopy());
						} else if (data->getLength() == 1) {
							*outVal = *reinterpret_cast<const uint8_t *>(data->getBytesNoCopy());
						}
					}
				}
				result->release();
			}
		}

		if (uuidData) uuidData->release();
		if (revNum) revNum->release();
		if (funcNum) funcNum->release();
		if (argNum) argNum->release();
		if (pkgArray) pkgArray->release();
		return true;
	}

	static void setClevoKbdBrightness(uint8_t brightness) {
		if (brightness == 0) {
			// Exact OEM LedKeyboardSetting.exe / FnKey.exe SetLedOnOff(0) sequence:
			callClevoDCHU(0x67, 0xF4000000); // ECMD 0xCA, 0x06, 0x00 (Brightness = 0)
			callClevoDCHU(0x67, 0xE0000007); // ECMD 0xC4, 0x0C, 0x00 (All zones OFF)
		} else {
			// Exact OEM LedKeyboardSetting.exe / FnKey.exe SetLedOnOff(1) + SetBrightnessValue(br):
			callClevoDCHU(0x67, 0xE007F001);               // ECMD 0xC4, 0x0C, 0x3F (All zones ON)
			callClevoDCHU(0x67, 0xF4000000 | brightness);  // ECMD 0xCA, 0x06, br
		}
	}

	static void setClevoKbdColor(uint8_t zone, uint32_t color) {
		// color is 0x00RRGGBB
		// Exact OEM CC.RGBKB::SetColor format: (Blue << 16) | (Red << 8) | Green
		uint32_t cset = ((color & 0x0000FF) << 16) | ((color & 0xFF0000) >> 8) | ((color & 0x00FF00) >> 8);
		uint32_t zoneCmd = 0xF0000000;
		if (zone == 1) zoneCmd = 0xF1000000;
		else if (zone == 2) zoneCmd = 0xF2000000;
		else if (zone == 3) zoneCmd = 0xF3000000;
		callClevoDCHU(0x67, zoneCmd | cset);
	}

	static void setClevoKbdAllZonesColor(uint32_t color) {
		setClevoKbdColor(0, color);
		setClevoKbdColor(1, color);
		setClevoKbdColor(2, color);
		setClevoKbdColor(3, color);
	}

	static void handleClevoEvent(uint32_t eventCode) {
		IOLog("SMCSuperIO: Clevo ACPI event received: 0x%04X\n", eventCode);
		switch (eventCode) {
			case 0x82: // Fn + + (Numpad) -> Brightness UP (0 -> 64 -> 128 -> 191 -> 255)
			case 0x21: {
				if (!sClevoOn || sClevoBrightness == 0) {
					sClevoOn = true;
					sClevoBrightness = 64;
					setClevoKbdAllZonesColor(sPresetColors[sClevoColorIdx]);
				} else if (sClevoBrightness < 128) {
					sClevoBrightness = 128;
				} else if (sClevoBrightness < 191) {
					sClevoBrightness = 191;
				} else {
					sClevoBrightness = 255;
				}
				sClevoLastNonZeroBrightness = sClevoBrightness;
				setClevoKbdBrightness(sClevoBrightness);
				if (sValBrightness) sValBrightness->setSilent(sClevoBrightness);
				if (sValMode) sValMode->setSilent(1);
				IOLog("SMCSuperIO: Keyboard brightness UP -> %u/255\n", sClevoBrightness);
				break;
			}
			case 0x81: // Fn + - (Numpad) -> Brightness DOWN (255 -> 191 -> 128 -> 64 -> 0 OFF)
			case 0x20: {
				if (!sClevoOn || sClevoBrightness <= 64) {
					sClevoBrightness = 0;
					sClevoOn = false;
				} else if (sClevoBrightness <= 128) {
					sClevoBrightness = 64;
				} else if (sClevoBrightness <= 191) {
					sClevoBrightness = 128;
				} else {
					sClevoBrightness = 191;
				}
				if (sClevoBrightness > 0) sClevoLastNonZeroBrightness = sClevoBrightness;
				setClevoKbdBrightness(sClevoBrightness);
				if (sValBrightness) sValBrightness->setSilent(sClevoBrightness);
				if (sValMode) sValMode->setSilent(sClevoOn ? 1 : 0);
				IOLog("SMCSuperIO: Keyboard brightness DOWN -> %u/255\n", sClevoBrightness);
				break;
			}
			case 0x9F: // Fn + * (Numpad) -> Toggle ON / OFF
			case 0x3F: {
				sClevoOn = !sClevoOn;
				if (sClevoOn) {
					sClevoBrightness = (sClevoLastNonZeroBrightness > 0) ? sClevoLastNonZeroBrightness : 255;
					setClevoKbdAllZonesColor(sPresetColors[sClevoColorIdx]);
					setClevoKbdBrightness(sClevoBrightness);
					IOLog("SMCSuperIO: Keyboard backlight TOGGLE ON (%u/255)\n", sClevoBrightness);
				} else {
					if (sClevoBrightness > 0) sClevoLastNonZeroBrightness = sClevoBrightness;
					sClevoBrightness = 0;
					setClevoKbdBrightness(0);
					IOLog("SMCSuperIO: Keyboard backlight TOGGLE OFF\n");
				}
				if (sValBrightness) sValBrightness->setSilent(sClevoOn ? sClevoBrightness : 0);
				if (sValMode) sValMode->setSilent(sClevoOn ? 1 : 0);
				break;
			}
			case 0x83: { // Fn + / (Numpad) -> Cycle Color
				sClevoColorIdx = (sClevoColorIdx + 1) % sNumPresetColors;
				uint32_t col = sPresetColors[sClevoColorIdx];
				if (!sClevoOn || sClevoBrightness == 0) {
					sClevoOn = true;
					sClevoBrightness = (sClevoLastNonZeroBrightness > 0) ? sClevoLastNonZeroBrightness : 255;
					setClevoKbdBrightness(sClevoBrightness);
					if (sValBrightness) sValBrightness->setSilent(sClevoBrightness);
					if (sValMode) sValMode->setSilent(1);
				}
				setClevoKbdAllZonesColor(col);
				for (int z = 0; z < 3; z++) {
					if (sValColor[z]) sValColor[z]->setSilent(col);
				}
				IOLog("SMCSuperIO: Keyboard color CYCLE -> 0x%06X (%zu/%zu)\n", col, sClevoColorIdx + 1, sNumPresetColors);
				break;
			}
			default:
				break;
		}
	}

	static IOReturn clevoAcpiNotifyHandler(void *target, void *refCon, UInt32 messageType, IOService *provider, void *messageArgument, vm_size_t argSize) {
		if (messageType == kIOACPIMessageDeviceNotification) {
			uint32_t eventCode = 0;
			if (callClevoDCHU(0x01, 0, &eventCode) && eventCode != 0) {
				handleClevoEvent(eventCode);
			}
		}
		return kIOReturnSuccess;
	}

	static void initClevoKbd() {
		static bool sKbdInited = false;
		if (sKbdInited) return;
		sKbdInited = true;

		// Default boot state: completely OFF (no unwanted white illumination during boot)
		setClevoKbdBrightness(0);
		sClevoBrightness = 0;
		sClevoOn = false;
		sClevoColorIdx = 4; // Cyan

		// Ensure both CPU and GPU fans start in clean EC Auto mode (bit 0 = Fan 1, bit 1 = Fan 2)
		callClevoDCHU(0x69, 0x01);
		IODelay(2000);
		callClevoDCHU(0x69, 0x02);

		// Enable Clevo ACPI keyboard events (0x46)
		callClevoDCHU(0x46, 0);

		// Register ACPI notification listener on DCHU (CLV0001)
		static IONotifier *sNotifier = nullptr;
		auto dchu = getDCHU();
		if (dchu && !sNotifier) {
			sNotifier = dchu->registerInterest(gIOGeneralInterest, &clevoAcpiNotifyHandler, nullptr, nullptr);
			IOLog("SMCSuperIO: Clevo ACPI notifier registered on DCHU\n");
		}
	}

	static IOACPIPlatformDevice *getECAcpiDevice() {
		static IOACPIPlatformDevice *cachedEC = nullptr;
		if (cachedEC) return cachedEC;

		auto dict = IOService::nameMatching("EC");
		if (!dict) return nullptr;

		auto iter = IOService::getMatchingServices(dict);
		dict->release();
		if (iter) {
			cachedEC = OSDynamicCast(IOACPIPlatformDevice, iter->getNextObject());
			if (cachedEC) cachedEC->retain();
			iter->release();
		}
		return cachedEC;
	}

	static bool callClevoECMD(uint8_t cmd, uint8_t fdat, uint8_t fbuf) {
		auto ec = getECAcpiDevice();
		if (!ec) return false;

		uint8_t buf[8] = { 0x03, 0x64, cmd, fdat, fbuf, 0x00, 0x00, 0x00 };
		auto dataObj = OSData::withBytes(buf, sizeof(buf));
		if (!dataObj) return false;

		OSObject *params[1] = { dataObj };
		OSObject *result = nullptr;
		IOReturn ret = ec->evaluateObject("ECMD", &result, params, 1);
		if (result) result->release();
		dataObj->release();
		return (ret == kIOReturnSuccess);
	}

	static constexpr SMC_KEY KeyLKSB = SMC_MAKE_IDENTIFIER('L','K','S','B');
	static constexpr SMC_KEY KeyLKSS = SMC_MAKE_IDENTIFIER('L','K','S','S');
	static constexpr SMC_KEY KeyMSLD = SMC_MAKE_IDENTIFIER('M','S','L','D');

	static constexpr SMC_KEY KeyKBBR = SMC_MAKE_IDENTIFIER('K','B','B','R');
	static constexpr SMC_KEY KeyKBC0 = SMC_MAKE_IDENTIFIER('K','B','C','0');
	static constexpr SMC_KEY KeyKBC1 = SMC_MAKE_IDENTIFIER('K','B','C','1');
	static constexpr SMC_KEY KeyKBC2 = SMC_MAKE_IDENTIFIER('K','B','C','2');
	static constexpr SMC_KEY KeyKBMD = SMC_MAKE_IDENTIFIER('K','B','M','D');

	const char* ECDeviceGeneric::getModelName() {
		return modelName;
	}

	uint8_t ECDeviceGeneric::getTachometerCount() {
		return tachometerCount;
	}

	uint16_t ECDeviceGeneric::updateTachometer(uint8_t index) {
		static uint16_t sSmoothedRpm[MaxTachometerCount] = { 1550, 1550, 0, 0, 0 };
		if (index >= MaxTachometerCount) return 0;

		uint8_t addr = (index == 0) ? 0xCE : 0xCF;
		if (tachometers[index].addr != 0 && tachometers[index].addr < 0x100) {
			addr = static_cast<uint8_t>(tachometers[index].addr);
		}

		uint8_t duty = (mmioArea != nullptr) ? mmioArea[addr] : 65;

		// Convert Clevo EC PWM duty (0..255) to RPM (0 or 1500..5200) matching updateTargets()
		uint16_t rpm = 0;
		if (duty == 0) {
			rpm = 0;
		} else if (duty < 64) {
			rpm = static_cast<uint16_t>((static_cast<uint32_t>(duty) * 1500U) / 64U);
		} else {
			rpm = static_cast<uint16_t>(1500U + ((static_cast<uint32_t>(duty - 64U) * (5200U - 1500U)) / (255U - 64U)));
		}

		if (sSmoothedRpm[index] == 0 || rpm == 0) {
			sSmoothedRpm[index] = rpm;
		} else {
			sSmoothedRpm[index] = static_cast<uint16_t>((static_cast<uint32_t>(sSmoothedRpm[index]) * 3U + rpm) / 4U);
		}
		return sSmoothedRpm[index];
	}

	const char *ECDeviceGeneric::getTachometerName(uint8_t index) {
		if (index == 0) return "CPU Fan";
		if (index == 1) return "GPU Fan";
		return "Fan";
	}

	uint8_t ECDeviceGeneric::getVoltageCount() {
		return 0;
	}

	float ECDeviceGeneric::updateVoltage(uint8_t index) {
		return 0;
	}

	const char *ECDeviceGeneric::getVoltageName(uint8_t index) {
		return "";
	}

	uint8_t ECDeviceGeneric::getTemperatureCount() {
		return 2;
	}

	float ECDeviceGeneric::updateTemperature(uint8_t index) {
		static float sSmoothedCpuTemp = 48.0f;
		static float sSmoothedGpuTemp = 40.0f;

		if (index == 0) {
			float rawTemp = 0.0f;

			// Prefer Clevo EC RAM hardware-filtered PECI CPU temp at MMIO offset 0x07
			if (mmioArea != nullptr) {
				uint8_t ec_temp = mmioArea[0x07];
				if (ec_temp >= 20 && ec_temp <= 105) {
					rawTemp = static_cast<float>(ec_temp);
				}
			}

			// Fallback to Intel Package DTS MSR if EC temp unavailable
			if (rawTemp < 20.0f) {
				uint64_t tjmax_msr = rdmsr64(0x1A2);
				uint8_t tjmax = (tjmax_msr >> 16) & 0x7F;
				if (tjmax == 0 || tjmax > 115) tjmax = 100;

				uint64_t msr = rdmsr64(0x1B1); // MSR_IA32_PACKAGE_THERM_STATUS
				if (msr & 0x80000000) {
					uint8_t delta = (msr >> 16) & 0x7F;
					if (delta < tjmax) rawTemp = static_cast<float>(tjmax - delta);
				}
			}

			if (rawTemp < 20.0f) rawTemp = 45.0f;
			sSmoothedCpuTemp = (sSmoothedCpuTemp * 0.8f) + (rawTemp * 0.2f);
			return sSmoothedCpuTemp;
		}

		if (index == 1) {
			float rawGpu = 40.0f;
			if (mmioArea != nullptr) {
				uint8_t g1 = mmioArea[0xCD];
				uint8_t g2 = mmioArea[0xC7]; // VGAT in DSDT
				if (g1 >= 20 && g1 <= 105) rawGpu = static_cast<float>(g1);
				else if (g2 >= 20 && g2 <= 105) rawGpu = static_cast<float>(g2);
			}
			sSmoothedGpuTemp = (sSmoothedGpuTemp * 0.8f) + (rawGpu * 0.2f);
			return sSmoothedGpuTemp;
		}

		return 0.0f;
	}

	const char *ECDeviceGeneric::getTemperatureName(uint8_t index) {
		if (index == 0) return "CPU Die";
		if (index == 1) return "GPU Die";
		return "Thermal Sensor";
	}

	void ECDeviceGeneric::setupKeys(VirtualSMCAPI::Plugin &vsmcPlugin) {
		VirtualSMCAPI::addKey(KeyFNum, vsmcPlugin.data,
			VirtualSMCAPI::valueWithUint8(getTachometerCount(), nullptr, SMC_KEY_ATTRIBUTE_CONST | SMC_KEY_ATTRIBUTE_READ));

		struct FanTypeDescStruct {
			uint8_t type {1};
			uint8_t zone {1};
			uint8_t location {0};
			uint8_t rsvd {0};
			char strFunction[12] {};
		};

		for (uint8_t index = 0; index < getTachometerCount(); ++index) {
			FanTypeDescStruct desc {};
			desc.type = 1;
			desc.zone = 1;
			lilu_os_strncpy(desc.strFunction, getTachometerName(index), sizeof(desc.strFunction));
			VirtualSMCAPI::addKey(KeyF0ID(index), vsmcPlugin.data,
				VirtualSMCAPI::valueWithData(reinterpret_cast<const SMC_DATA *>(&desc), sizeof(desc), SmcKeyTypeFds, nullptr, SMC_KEY_ATTRIBUTE_CONST | SMC_KEY_ATTRIBUTE_READ));

			VirtualSMCAPI::addKey(KeyF0Ac(index), vsmcPlugin.data,
				VirtualSMCAPI::valueWithFp(0, SmcKeyTypeFpe2, new TachometerKey(getSmcSuperIO(), this, index)));

			VirtualSMCAPI::addKey(KeyF0Md(index), vsmcPlugin.data,
				VirtualSMCAPI::valueWithUint8(0, new ManualKey(getSmcSuperIO(), this, index), SMC_KEY_ATTRIBUTE_WRITE | SMC_KEY_ATTRIBUTE_READ));

			VirtualSMCAPI::addKey(KeyF0Mn(index), vsmcPlugin.data,
				VirtualSMCAPI::valueWithFp(1500, SmcKeyTypeFpe2, new MinKey(getSmcSuperIO(), this, index), SMC_KEY_ATTRIBUTE_WRITE | SMC_KEY_ATTRIBUTE_READ));

			VirtualSMCAPI::addKey(KeyF0Mx(index), vsmcPlugin.data,
				VirtualSMCAPI::valueWithFp(5200, SmcKeyTypeFpe2, new MaxKey(getSmcSuperIO(), this, index), SMC_KEY_ATTRIBUTE_WRITE | SMC_KEY_ATTRIBUTE_READ));

			VirtualSMCAPI::addKey(KeyF0Tg(index), vsmcPlugin.data,
				VirtualSMCAPI::valueWithFp(1500, SmcKeyTypeFpe2, new TargetKey(getSmcSuperIO(), this, index), SMC_KEY_ATTRIBUTE_WRITE | SMC_KEY_ATTRIBUTE_READ));
		}

		// CPU & GPU Temperature Sensors for AppleSMC
		static constexpr SMC_KEY KeyTC0D = SMC_MAKE_IDENTIFIER('T','C','0','D');
		static constexpr SMC_KEY KeyTG0D = SMC_MAKE_IDENTIFIER('T','G','0','D');

		// TC0P (CPU Proximity) & TC0D (CPU Die)
		VirtualSMCAPI::addKey(KeyTC0P(0), vsmcPlugin.data,
			VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TemperatureKey(getSmcSuperIO(), this, 0)));
		VirtualSMCAPI::addKey(KeyTC0D, vsmcPlugin.data,
			VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TemperatureKey(getSmcSuperIO(), this, 0)));

		// TG0P (GPU Proximity) & TG0D (GPU Die)
		VirtualSMCAPI::addKey(KeyTG0P(0), vsmcPlugin.data,
			VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TemperatureKey(getSmcSuperIO(), this, 1)));
		VirtualSMCAPI::addKey(KeyTG0D, vsmcPlugin.data,
			VirtualSMCAPI::valueWithSp(0, SmcKeyTypeSp78, new TemperatureKey(getSmcSuperIO(), this, 1)));

		// Native Apple keyboard backlight keys
		struct lkb { uint8_t val {255}; uint8_t state {1}; } lkbVal {};
		struct lks { uint8_t unknown0 {0}; uint8_t unknown1 {1}; } lksVal {};

		VirtualSMCAPI::addKey(KeyLKSB, vsmcPlugin.data,
			VirtualSMCAPI::valueWithData(reinterpret_cast<const SMC_DATA *>(&lkbVal), sizeof(lkbVal),
			SmcKeyTypeLkb, new ClevoBrightnessLKSBKey(), SMC_KEY_ATTRIBUTE_READ | SMC_KEY_ATTRIBUTE_WRITE));

		VirtualSMCAPI::addKey(KeyLKSS, vsmcPlugin.data,
			VirtualSMCAPI::valueWithData(reinterpret_cast<const SMC_DATA *>(&lksVal), sizeof(lksVal),
			SmcKeyTypeLks, nullptr, SMC_KEY_ATTRIBUTE_READ | SMC_KEY_ATTRIBUTE_WRITE));

		VirtualSMCAPI::addKey(KeyMSLD, vsmcPlugin.data, VirtualSMCAPI::valueWithUint8(0));

		// Custom Clevo Backlight & RGB keys
		auto brKey = new ClevoBrightnessKey();
		sValBrightness = brKey;
		VirtualSMCAPI::addKey(KeyKBBR, vsmcPlugin.data,
			VirtualSMCAPI::valueWithUint8(0, brKey, SMC_KEY_ATTRIBUTE_READ | SMC_KEY_ATTRIBUTE_WRITE));

		uint32_t defaultColor = 0x0000FFFF;
		for (int z = 0; z < 3; z++) {
			auto colKey = new ClevoColorKey(z);
			sValColor[z] = colKey;
			SMC_KEY k = (z == 0) ? KeyKBC0 : ((z == 1) ? KeyKBC1 : KeyKBC2);
			VirtualSMCAPI::addKey(k, vsmcPlugin.data,
				VirtualSMCAPI::valueWithUint32(defaultColor, colKey, SMC_KEY_ATTRIBUTE_READ | SMC_KEY_ATTRIBUTE_WRITE));
		}

		auto modeKey = new ClevoModeKey();
		sValMode = modeKey;
		VirtualSMCAPI::addKey(KeyKBMD, vsmcPlugin.data,
			VirtualSMCAPI::valueWithUint8(0, modeKey, SMC_KEY_ATTRIBUTE_READ | SMC_KEY_ATTRIBUTE_WRITE));

		initClevoKbd();

		setupExtraKeys(vsmcPlugin);

		qsort(const_cast<VirtualSMCKeyValue *>(vsmcPlugin.data.data()), vsmcPlugin.data.size(), sizeof(VirtualSMCKeyValue), VirtualSMCKeyValue::compare);
	}

	void ECDeviceGeneric::updateTargets() {
		// 1. Flush any deferred keyboard backlight commands on the workloop thread (outside VirtualSMC lock)
		if (atomic_exchange_explicit(&sDirtyMode, false, memory_order_acquire)) {
			uint8_t mode = atomic_load_explicit(&sPendingMode, memory_order_relaxed);
			sClevoOn = (mode != 0);
			if (mode == 0) {
				if (sClevoBrightness > 0) sClevoLastNonZeroBrightness = sClevoBrightness;
				sClevoBrightness = 0;
				setClevoKbdBrightness(0);
			} else {
				uint8_t br = (sClevoBrightness > 0) ? sClevoBrightness : ((sClevoLastNonZeroBrightness > 0) ? sClevoLastNonZeroBrightness : 255);
				sClevoBrightness = br;
				sClevoLastNonZeroBrightness = br;
				setClevoKbdBrightness(br);
			}
		}

		if (atomic_exchange_explicit(&sDirtyBrightness, false, memory_order_acquire)) {
			uint8_t br = atomic_load_explicit(&sPendingBrightness, memory_order_relaxed);
			if (br > 0) sClevoLastNonZeroBrightness = br;
			sClevoBrightness = br;
			sClevoOn = (br > 0);
			setClevoKbdBrightness(br);
		}

		for (uint8_t z = 0; z < 3; z++) {
			if (atomic_exchange_explicit(&sDirtyColor[z], false, memory_order_acquire)) {
				uint32_t col = atomic_load_explicit(&sPendingColor[z], memory_order_relaxed);
				setClevoKbdColor(z, col);
				if (z == 0) {
					setClevoKbdColor(3, col); // Also send single-zone All (0xF3 -> 0xCA 0x07)
					for (size_t i = 0; i < sNumPresetColors; i++) {
						if (sPresetColors[i] == (col & 0x00FFFFFF)) {
							sClevoColorIdx = i;
							break;
						}
					}
				}
			}
		}

		// 2. Smooth & safe Fan Control on the workloop thread
		static bool sInAutoMode = true;
		static uint8_t sCurrentDuty[2] = { 65, 65 };

		bool anyManual = false;
		for (uint8_t i = 0; i < tachometerCount && i < 2; i++) {
			if (getManualValue(i)) anyManual = true;
		}

		if (!anyManual) {
			if (!sInAutoMode) {
				// Restore EC Auto mode on both Fan 1 (0x01) and Fan 2 (0x02)
				if (!callClevoECMD(0xC1, 0xFF, 0x01)) {
					callClevoDCHU(0x69, 0x01);
				}
				IODelay(2000);
				if (!callClevoECMD(0xC1, 0xFF, 0x02)) {
					callClevoDCHU(0x69, 0x02);
				}
				sInAutoMode = true;
			}
			if (mmioArea != nullptr) {
				sCurrentDuty[0] = mmioArea[0xCE] >= 64 ? mmioArea[0xCE] : 65;
				sCurrentDuty[1] = mmioArea[0xCF] >= 64 ? mmioArea[0xCF] : 65;
			}
			return;
		}

		sInAutoMode = false;

		for (uint8_t i = 0; i < tachometerCount && i < 2; i++) {
			if (!getManualValue(i)) {
				continue;
			}

			uint16_t t = getTargetValue(i);
			uint8_t targetDuty = 64;
			if (t <= 1500) targetDuty = 64;
			else if (t >= 5200) targetDuty = 255;
			else targetDuty = static_cast<uint8_t>(64U + ((static_cast<uint32_t>(t - 1500U) * (255U - 64U)) / (5200U - 1500U)));

			int diff = static_cast<int>(targetDuty) - static_cast<int>(sCurrentDuty[i]);
			if (diff > -3 && diff < 3) {
				continue; // Within deadband, do not spam EC
			}

			// Slew-rate limit max step to ±12 duty per 500ms tick so fan transitions smoothly
			if (diff > 12) sCurrentDuty[i] += 12;
			else if (diff < -12) sCurrentDuty[i] -= 12;
			else sCurrentDuty[i] = targetDuty;

			uint8_t fanId = i + 1; // 0x01 = CPU Fan, 0x02 = GPU Fan
			callClevoECMD(0xC1, fanId, sCurrentDuty[i]);
			IODelay(1500);
		}
	}

	ECDeviceGeneric::ECDeviceGeneric(IORegistryEntry *lpc) {
		device = lpc;

		if (WIOKit::getOSDataValue(lpc, "fan-count", tachometerCount) && (tachometerCount == 0 || tachometerCount >= MaxTachometerCount)) {
			tachometerCount = 1;
		}

		// Map Clevo EC RAM directly via SystemMemory MMIO at 0xFE0B0100 (0x100 bytes)
		// This completely avoids I/O port 0x62/0x66 races with AppleACPIEC!
		supportsMMIO = false;
		supportsPMIO = true;
		mmioDesc = IOMemoryDescriptor::withPhysicalAddress(0xFE0B0100, 0x100, kIODirectionIn);
		if (mmioDesc != nullptr) {
			if (mmioDesc->prepare() == kIOReturnSuccess) {
				mmioMap = mmioDesc->map();
				if (mmioMap != nullptr) {
					mmioArea = reinterpret_cast<volatile uint8_t *>(mmioMap->getVirtualAddress());
					IOLog("SMCSuperIO: Mapped Clevo EC RAM via MMIO at 0xFE0B0100\n");
				}
			}
		}

		for (uint32_t i = 0; i < tachometerCount; i++) {
			setMinValue(i, 1500);
			setMaxValue(i, 5200);
			setTargetValue(i, 1500);
			setManualValue(i, 0);

			char name[64];
			snprintf(name, sizeof(name), "fan%u-addr", i);
			WIOKit::getOSDataValue(lpc, name, tachometers[i].addr);

			snprintf(name, sizeof(name), "fan%u-size", i);
			uint32_t tmp = 1;
			if (WIOKit::getOSDataValue(lpc, name, tmp) && (tmp == 0 || tmp > sizeof(uint16_t)))
				tmp = 1;
			tachometers[i].size = tmp;

			tmp = 0;
			snprintf(name, sizeof(name), "fan%u-big", i);
			if (WIOKit::getOSDataValue(lpc, name, tmp) && (tmp != 0 && tmp != 1))
				tmp = 0;
			tachometers[i].bigEndian = tmp != 0;

			tmp = 0;
			snprintf(name, sizeof(name), "fan%u-inverse", i);
			if (WIOKit::getOSDataValue(lpc, name, tmp) && (tmp != 0 && tmp != 1))
				tmp = 0;
			tachometers[i].inverse = tmp != 0;

			snprintf(name, sizeof(name), "fan%u-mul", i);
			if (WIOKit::getOSDataValue(lpc, name, tachometers[i].mul) && tachometers[i].mul == 0)
				tachometers[i].mul = 1;

			snprintf(name, sizeof(name), "fan%u-div", i);
			if (WIOKit::getOSDataValue(lpc, name, tachometers[i].div) && tachometers[i].div == 0)
				tachometers[i].div = 1;
			
			snprintf(name, sizeof(name), "fan%u-dividend", i);
			WIOKit::getOSDataValue(lpc, name, tachometers[i].dividend);

			DBGLOG("ssio", "added tach%u at 0x%04X (%d bytes, %s)", i, tachometers[i].addr, tachometers[i].size,
				   tachometers[i].bigEndian ? "big" : "little");
		}

		initClevoKbd();
	}

	ECDevice* ECDeviceGeneric::detect(SMCSuperIO* sio, const char *name, IORegistryEntry *lpc) {
		if (strcmp(name, "generic") != 0)
			return nullptr;

		DBGLOG("ssio", "initialising Generic EC");
		return new ECDeviceGeneric(lpc);
	}
}
