/*
 * SSDT-CLEVOSENSE — EC access and Single-Zone RGB control for Acer Aspire 7 A715-59G
 * Remapped for Acer Aspire 7 A715-59G EC RAM at 0xFE0B0100, RAM3 at 0xFE0B0300, and WMI at \_SB.WMI_
 */
DefinitionBlock ("", "SSDT", 2, "NITRO", "NITROEC", 0x00001000)
{
    External (_SB_.PC00.GMHB, MethodObj)    // 0 Arguments
    External (_SB_.PC00.LPCB.EC__.ECMD, MethodObj) // 1 Argument
    External (_SB_.BAT0, DeviceObj)
    External (_SB_.WMI_.CC20, MethodObj)    // 3 Arguments
    External (_SB_.WMI_.CC30, MethodObj)    // 3 Arguments
    External (BAEE, FieldUnitObj)
    External (BSCP, FieldUnitObj)
    External (BTCP, FieldUnitObj)

    Scope (\_SB)
    {
        Device (NTRO)
        {
            Name (_HID, "NTRO0001")  // _HID: Hardware ID
            Name (_UID, Zero)        // _UID: Unique ID

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (_OSI ("Darwin"))
                {
                    Return (0x0F)
                }

                Return (Zero)
            }

            // Initialization: runs early during macOS kernel boot
            Method (_INI, 0, NotSerialized)
            {
                If (CondRefOf (\_SB.DCHU.HKDR))
                {
                    \_SB.DCHU.HKDR = One
                }

                If (CondRefOf (\_SB.PC00.LPCB.EC.ECMD))
                {
                    // Enable Clevo EC keyboard backlight hotkey events (Fn + / * - +)
                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08)
                    {
                        0x03, 0x00, 0xC4, 0x05, 0x01, 0x00, 0x00, 0x00
                    })

                    // Exact OEM Clevo ControlCenter OFF sequence (SetLedOnOff(0)):
                    // 1. Brightness = 0 (0xCA, 0x06, 0x00, 0x00, 0x00)
                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08)
                    {
                        0x05, 0x00, 0xCA, 0x06, 0x00, 0x00, 0x00, 0x00
                    })
                    // 2. All zone enable mask = 0x00 (0xC4, 0x0C, 0x00)
                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08)
                    {
                        0x03, 0x00, 0xC4, 0x0C, 0x00, 0x00, 0x00, 0x00
                    })
                }

                KBBH = Zero
            }

            // Interface version: 4
            Method (VERS, 0, NotSerialized)
            {
                Return (0x04)
            }

            // EC RAM window 0x00..0xFF at 0xFE0B0100 (Region RAM of Aspire 7 A715-59G)
            OperationRegion (ERDM, SystemMemory, 0xFE0B0100, 0x0100)
            Field (ERDM, ByteAcc, Lock, Preserve)
            {
                BUF0,   2048
            }

            // Read EC bytes 0x00..0xFF -> Buffer (0x100)
            Method (RDMP, 0, Serialized)
            {
                Return (BUF0)
            }

            // Read 1 single byte from EC RAM
            Method (RE1B, 1, Serialized)
            {
                OperationRegion (ER1B, SystemMemory, (0xFE0B0100 + Arg0), One)
                Field (ER1B, ByteAcc, Lock, Preserve)
                {
                    BYT0,   8
                }
                Return (BYT0)
            }

            // EC RAM3 window at 0xFE0B0300 (Region RAM3: RGB keyboard & Quiet mode)
            OperationRegion (ERM3, SystemMemory, 0xFE0B0300, 0x0100)
            Field (ERM3, ByteAcc, Lock, Preserve)
            {
                Offset (0x80), 
                KLCR,   8, 
                KLCG,   8, 
                KLCB,   8, 
                KMCR,   8, 
                KMCG,   8, 
                KMCB,   8, 
                KRCR,   8, 
                KRCG,   8, 
                KRCB,   8, 
                KBBH,   8, 
                FANQ,   8
            }

            // Read Single-Zone RGB: returns 4 bytes (Red, Green, Blue, Brightness)
            Method (RRGB, 0, Serialized)
            {
                Local0 = Buffer (0x04) { 0 }
                Local0 [Zero] = KLCR
                Local0 [One] = KLCG
                Local0 [0x02] = KLCB
                Local0 [0x03] = KBBH
                Return (Local0)
            }

            // Write Single-Zone RGB: Arg0 is 4 bytes (Red, Green, Blue, Brightness)
            // Broadcasts the RGB color atomically across all 3 hardware channels via Clevo ECMD and updates RAM3 mirror
            Method (WRGB, 1, Serialized)
            {
                If ((SizeOf (Arg0) >= 0x04))
                {
                    CreateByteField (Arg0, Zero, RED0)
                    CreateByteField (Arg0, One, GRN0)
                    CreateByteField (Arg0, 0x02, BLU0)
                    CreateByteField (Arg0, 0x03, BRT0)

                    // 1. Update EC RAM3 mirror (preserve color when turning off)
                    If (((BRT0 > Zero) || (((RED0 | GRN0) | BLU0) != Zero)))
                    {
                        KLCR = RED0
                        KLCG = GRN0
                        KLCB = BLU0

                        KMCR = RED0
                        KMCG = GRN0
                        KMCB = BLU0

                        KRCR = RED0
                        KRCG = GRN0
                        KRCB = BLU0
                    }

                    KBBH = BRT0

                    // 2. Hardware actuation via Clevo EC Mailbox (ECMD)
                    // Exact command sequence verified from OEM LedKeyboardSetting.exe & FnKey.exe
                    If (CondRefOf (\_SB.PC00.LPCB.EC.ECMD))
                    {
                        If ((BRT0 > Zero))
                        {
                            // Enable all LED zones mask (OEM 0xE007F001 -> 0xC4, 0x0C, 0x3F)
                            \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08)
                            {
                                0x03, 0x00, 0xC4, 0x0C, 0x3F, 0x00, 0x00, 0x00
                            })

                            // Set Brightness via OEM 0xF4000000|br -> 0xCA, 0x06, BRT0, 0x00, BRT0
                            Local0 = Buffer (0x08)
                            {
                                0x05, 0x00, 0xCA, 0x06, 0x00, 0x00, 0x00, 0x00
                            }
                            Local0 [0x04] = BRT0
                            Local0 [0x06] = BRT0
                            \_SB.PC00.LPCB.EC.ECMD (Local0)

                            // Set RGB Color (OEM CC.RGBKB::SetColor format: Blue, Red, Green)
                            // Send Left (0x03), Mid (0x04), Right (0x05) & All (0x07)
                            Local1 = Buffer (0x08)
                            {
                                0x05, 0x00, 0xCA, 0x03, 0x00, 0x00, 0x00, 0x00
                            }
                            Local1 [0x04] = BLU0
                            Local1 [0x05] = RED0
                            Local1 [0x06] = GRN0
                            \_SB.PC00.LPCB.EC.ECMD (Local1)

                            Local1 [0x03] = 0x04
                            \_SB.PC00.LPCB.EC.ECMD (Local1)

                            Local1 [0x03] = 0x05
                            \_SB.PC00.LPCB.EC.ECMD (Local1)

                            Local1 [0x03] = 0x07
                            \_SB.PC00.LPCB.EC.ECMD (Local1)
                        }
                        Else
                        {
                            // Exact OEM LedKeyboardSetting.exe SetLedOnOff(0) sequence:
                            // 1. Brightness = 0 (OEM 0xF4000000 -> 0xCA, 0x06, 0x00, 0x00, 0x00)
                            \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08)
                            {
                                0x05, 0x00, 0xCA, 0x06, 0x00, 0x00, 0x00, 0x00
                            })

                            // 2. All zones OFF mask (OEM 0xE0000007 -> 0xC4, 0x0C, 0x00)
                            \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08)
                            {
                                0x03, 0x00, 0xC4, 0x0C, 0x00, 0x00, 0x00, 0x00
                            })
                        }
                    }
                }

                Return (Zero)
            }

            // Intel PCU registers for CPU package power & thermal
            Method (RPCU, 0, Serialized)
            {
                Local0 = Buffer (0x20) { 0 }
                If (_OSI ("Darwin"))
                {
                    If (CondRefOf (\_SB.PC00.GMHB))
                    {
                        OperationRegion (PCUR, SystemMemory, (\_SB.PC00.GMHB () + 0x5900), 0x0100)
                        Field (PCUR, DWordAcc, NoLock, Preserve)
                        {
                            Offset (0x28), 
                            ENP0,   32, 
                            ENP1,   32, 
                            Offset (0x38), 
                            UNIT,   32, 
                            ENPK,   32, 
                            Offset (0x48), 
                            GTPS,   32, 
                            Offset (0x78), 
                            TPKG,   32, 
                            TPP0,   32, 
                            TPP1,   32
                        }

                        CreateDWordField (Local0, Zero, R000)
                        CreateDWordField (Local0, 0x04, R004)
                        CreateDWordField (Local0, 0x08, R008)
                        CreateDWordField (Local0, 0x0C, R00C)
                        CreateDWordField (Local0, 0x10, R010)
                        CreateDWordField (Local0, 0x14, R014)
                        CreateDWordField (Local0, 0x18, R018)
                        CreateDWordField (Local0, 0x1C, R01C)
                        R000 = ENP0
                        R004 = ENP1
                        R008 = UNIT
                        R00C = ENPK
                        R010 = GTPS
                        R014 = TPKG
                        R018 = TPP0
                        R01C = TPP1
                    }
                }

                Return (Local0)
            }

            // Clevo Fan & Power Profile State Mirror
            Name (FMOD, One)   // 1 = Auto, 2 = Max, 3 = Custom
            Name (PMOD, One)   // 0 = Quiet, 1 = Balanced, 4 = Performance

            // WMBX: Emulates Acer Gaming WMI opcodes via Clevo EC Mailbox (ECMD)
            Method (WMBX, 2, Serialized)
            {
                If (_OSI ("Darwin"))
                {
                    // 1. Get Fan Behavior (0x0F)
                    If ((ToInteger (Arg0) == 0x0F))
                    {
                        Local0 = Buffer (0x04) { 0x00, 0x00, 0x00, 0x00 }
                        Local1 = (FMOD & 0x03)
                        Local0 [One] = (Local1 | (Local1 << 0x06))
                        Return (Local0)
                    }

                    // 2. Set Fan Behavior (0x0E)
                    If ((ToInteger (Arg0) == 0x0E))
                    {
                        If ((SizeOf (Arg1) >= 0x03))
                        {
                            Local2 = DerefOf (Arg1 [0x02])
                            If ((Local2 == 0x41)) // Auto
                            {
                                FMOD = One
                                If (CondRefOf (\_SB.PC00.LPCB.EC.ECMD))
                                {
                                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08) { 0x03, 0x00, 0xC1, 0xFF, 0x01, 0x00, 0x00, 0x00 })
                                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08) { 0x03, 0x00, 0xC1, 0xFF, 0x02, 0x00, 0x00, 0x00 })
                                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08) { 0x03, 0x00, 0xB8, 0xC3, 0xA2, 0x00, 0x00, 0x00 })
                                }
                            }
                            ElseIf ((Local2 == 0x82)) // Max
                            {
                                FMOD = 0x02
                                If (CondRefOf (\_SB.PC00.LPCB.EC.ECMD))
                                {
                                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08) { 0x03, 0x00, 0xB8, 0xC2, 0xA2, 0x00, 0x00, 0x00 })
                                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08) { 0x03, 0x00, 0xC1, 0x01, 0xFF, 0x00, 0x00, 0x00 })
                                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08) { 0x03, 0x00, 0xC1, 0x02, 0xFF, 0x00, 0x00, 0x00 })
                                }
                            }
                            ElseIf ((Local2 == 0xC3)) // Custom
                            {
                                FMOD = 0x03
                            }
                        }
                        Return (Buffer (0x04) { 0x00, 0x00, 0x00, 0x00 })
                    }

                    // 3. Set Fan Speed (0x10)
                    If ((ToInteger (Arg0) == 0x10))
                    {
                        If ((SizeOf (Arg1) >= 0x02))
                        {
                            // Duty = (percent * 255) / 100
                            Local1 = ((DerefOf (Arg1 [One]) * 0xFF) / 0x64)
                            If (CondRefOf (\_SB.PC00.LPCB.EC.ECMD))
                            {
                                If ((DerefOf (Arg1 [Zero]) == One)) // CPU Fan
                                {
                                    Local3 = Buffer (0x08) { 0x03, 0x00, 0xC1, 0x01, 0x00, 0x00, 0x00, 0x00 }
                                    Local3 [0x04] = Local1
                                    \_SB.PC00.LPCB.EC.ECMD (Local3)
                                }
                                ElseIf ((DerefOf (Arg1 [Zero]) == 0x04)) // GPU Fan
                                {
                                    Local3 = Buffer (0x08) { 0x03, 0x00, 0xC1, 0x02, 0x00, 0x00, 0x00, 0x00 }
                                    Local3 [0x04] = Local1
                                    \_SB.PC00.LPCB.EC.ECMD (Local3)
                                }
                            }
                        }
                        Return (Buffer (0x04) { 0x00, 0x00, 0x00, 0x00 })
                    }

                    // 4. Get Misc / Platform Profile (0x17)
                    If ((ToInteger (Arg0) == 0x17))
                    {
                        If ((SizeOf (Arg1) >= One))
                        {
                            If ((DerefOf (Arg1 [Zero]) == 0x0A)) // Supported profiles
                            {
                                Return (Buffer (0x04) { 0x00, 0x13, 0x00, 0x00 })
                            }
                            If ((DerefOf (Arg1 [Zero]) == 0x0B)) // Current profile
                            {
                                Local0 = Buffer (0x04) { 0x00, 0x00, 0x00, 0x00 }
                                Local0 [One] = PMOD
                                Return (Local0)
                            }
                        }
                        Return (Buffer (0x04) { 0x00, 0x00, 0x00, 0x00 })
                    }

                    // 5. Set Misc / Platform Profile (0x16)
                    If ((ToInteger (Arg0) == 0x16))
                    {
                        If ((SizeOf (Arg1) >= 0x02))
                        {
                            If ((DerefOf (Arg1 [Zero]) == 0x0B))
                            {
                                Local4 = DerefOf (Arg1 [One])
                                If (CondRefOf (\_SB.PC00.LPCB.EC.ECMD))
                                {
                                    If ((Local4 == Zero)) // Quiet
                                    {
                                        PMOD = Zero
                                        \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08) { 0x03, 0x00, 0xD8, 0x01, 0x02, 0x00, 0x00, 0x00 })
                                    }
                                    ElseIf ((Local4 == One)) // Balanced
                                    {
                                        PMOD = One
                                        \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08) { 0x03, 0x00, 0xD8, 0x01, 0x03, 0x00, 0x00, 0x00 })
                                    }
                                    ElseIf ((Local4 == 0x04)) // Performance
                                    {
                                        PMOD = 0x04
                                        \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08) { 0x03, 0x00, 0xD8, 0x01, 0x01, 0x00, 0x00, 0x00 })
                                    }
                                }
                            }
                        }
                        Return (Buffer (0x04) { 0x00, 0x00, 0x00, 0x00 })
                    }

                    // 6. Get Keyboard Backlight (0x15)
                    If ((ToInteger (Arg0) == 0x15))
                    {
                        Return (Buffer (0x04) { 0x00, 0x01, 0x00, 0x00 })
                    }

                    Return (Buffer (0x04) { 0x00, 0x00, 0x00, 0x00 })
                }

                Return (Buffer (0x04)
                {
                     0xFF, 0xFF, 0xFF, 0xFF
                })
            }

            // WMI Write via CC30 (fallback)
            Method (WMAX, 2, Serialized)
            {
                Return (Buffer (0x04)
                {
                     0x00, 0x00, 0x00, 0x00
                })
            }

            Name (CHGE, One)

            // Battery health WMI emulation for Clevo FlexiCharger:
            // Arg0 = Method/Opcode (0x14 = GetHealth / Status, 0x15 = SetHealth)
            // Arg1 = Buffer in
            Method (WMEX, 2, Serialized)
            {
                If (_OSI ("Darwin"))
                {
                    // 0x14: GetBatteryHealthControlStatus
                    If ((Arg0 == 0x14))
                    {
                        Local0 = Buffer (0x04) { 0x01, 0x00, 0x00, 0x00 }
                        // Check if FlexiCharger is enabled: BAEE == 2 or (BAEE & 2)
                        If (CondRefOf (\BAEE))
                        {
                            If ((\BAEE & 0x02))
                            {
                                If (CondRefOf (\BTCP))
                                {
                                    Local1 = \BTCP
                                    If (((Local1 >= 0x32) && (Local1 <= 0x64)))
                                    {
                                        Local0 [0x03] = Local1
                                    }
                                    Else
                                    {
                                        Local0 [0x03] = 0x50 // default to 80% if uninitialized
                                    }
                                }
                                Else
                                {
                                    Local0 [0x03] = 0x50 // default 80%
                                }
                            }
                            Else
                            {
                                Local0 [0x03] = Zero // 0 = off / 100%
                            }
                        }
                        Else
                        {
                            Local0 [0x03] = CHGE
                        }
                        Return (Local0)
                    }

                    // 0x15: SetBatteryHealthControl
                    If ((Arg0 == 0x15))
                    {
                        If ((SizeOf (Arg1) >= 0x03))
                        {
                            CreateByteField (Arg1, 0x02, ENBL)
                            If (((ENBL == Zero) || (ENBL >= 0x64)))
                            {
                                CHGE = Zero
                                // Limit OFF: Stop 100%, Start 95%, Enable 0
                                If (CondRefOf (\BAEE)) { \BAEE = Zero }
                                If (CondRefOf (\BSCP)) { \BSCP = 0x5F } // 95%
                                If (CondRefOf (\BTCP)) { \BTCP = 0x64 } // 100%

                                If (CondRefOf (\_SB.PC00.LPCB.EC.ECMD))
                                {
                                    \_SB.PC00.LPCB.EC.ECMD (Buffer (0x08)
                                    {
                                        0x04, 0x00, 0xCB, 0x64, 0x5F, 0x00, 0x00, 0x00
                                    })
                                }
                            }
                            Else
                            {
                                Local1 = 0x50 // Default 80%
                                If ((ENBL == One))
                                {
                                    Local1 = 0x50
                                }
                                ElseIf (((ENBL >= 0x32) && (ENBL <= 0x5F))) // 50% - 95%
                                {
                                    Local1 = ENBL
                                }
                                CHGE = Local1

                                // Start percentage: Stop - 10, minimum 40%
                                Local2 = (Local1 - 0x0A)
                                If ((Local2 < 0x28)) { Local2 = 0x28 }

                                If (CondRefOf (\BAEE)) { \BAEE = 0x02 }
                                If (CondRefOf (\BSCP)) { \BSCP = Local2 }
                                If (CondRefOf (\BTCP)) { \BTCP = Local1 }

                                If (CondRefOf (\_SB.PC00.LPCB.EC.ECMD))
                                {
                                    Local3 = Buffer (0x08) { 0x04, 0x00, 0xCB, 0x00, 0x00, 0x02, 0x00, 0x00 }
                                    Local3 [0x03] = Local1
                                    Local3 [0x04] = Local2
                                    \_SB.PC00.LPCB.EC.ECMD (Local3)
                                }
                            }

                            If (CondRefOf (\_SB.BAT0))
                            {
                                Notify (\_SB.BAT0, 0x80)
                            }
                        }

                        // Return success: status byte 0 = 0x00
                        Return (Buffer (0x02) { 0x00, 0x00 })
                    }
                }

                Return (Buffer (0x04) { 0xFF, 0xFF, 0xFF, 0xFF })
            }
        }
    }

    External (_SB_.DCHU, DeviceObj)
    External (_SB_.DCHU.HKDR, IntObj)
    External (_SB_.DCHU.EVNT, IntObj)
    External (_SB_.PC00.LPCB.EC__, DeviceObj)
    External (_SB_.PC00.LPCB.EC__.XQ50, MethodObj)

    Scope (\_SB.PC00.LPCB.EC)
    {
        Method (_Q50, 0, NotSerialized)
        {
            // Ensure Clevo Hotkey Driver flag is active
            If (CondRefOf (\_SB.DCHU.HKDR))
            {
                \_SB.DCHU.HKDR = One
            }
            
            // Read OEM4 hotkey code directly from EC RAM SystemMemory at offset 0xCC
            Local0 = \_SB.NTRO.RE1B (0xCC)
            
            // Fn + / (Cycle Color) -> Clevo DCHU event 0x83
            If ((Local0 == 0x80))
            {
                If (CondRefOf (\_SB.DCHU.EVNT))
                {
                    \_SB.DCHU.EVNT = 0x83
                    Notify (\_SB.DCHU, 0x83)
                }
                Return (Zero)
            }

            // Fn + * (Toggle Backlight On/Off) -> Clevo DCHU event 0x9F
            If (((Local0 == 0x9F) || (Local0 == 0x3F)))
            {
                If (CondRefOf (\_SB.DCHU.EVNT))
                {
                    \_SB.DCHU.EVNT = 0x9F
                    Notify (\_SB.DCHU, 0x9F)
                }
                Return (Zero)
            }

            // Fn + - (Brightness Down) -> Clevo DCHU event 0x81
            If (((Local0 == 0x81) || (Local0 == 0x20)))
            {
                If (CondRefOf (\_SB.DCHU.EVNT))
                {
                    \_SB.DCHU.EVNT = 0x81
                    Notify (\_SB.DCHU, 0x81)
                }
                Return (Zero)
            }

            // Fn + + (Brightness Up) -> Clevo DCHU event 0x82
            If (((Local0 == 0x82) || (Local0 == 0x21)))
            {
                If (CondRefOf (\_SB.DCHU.EVNT))
                {
                    \_SB.DCHU.EVNT = 0x82
                    Notify (\_SB.DCHU, 0x82)
                }
                Return (Zero)
            }

            // Forward everything else to OEM XQ50
            If (CondRefOf (\_SB.PC00.LPCB.EC.XQ50))
            {
                \_SB.PC00.LPCB.EC.XQ50 ()
            }
            Return (Zero)
        }
    }
}
