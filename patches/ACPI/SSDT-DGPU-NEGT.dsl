DefinitionBlock ("", "SSDT", 2, "ACER", "DGPUNEGT", 0x00000001)
{
    External (_SB_.PC00.PEG1.PEGP, DeviceObj)
    External (_SB_.PC00.PEG1.PEGP.NEGT, MethodObj)    // 1 Arguments
    External (_SB_.PC00.PEG1.PEGP.OMPR, IntObj)
    External (_SB_.PC00.PEG1.PEGP.XPS0, MethodObj)    // 0 Arguments
    External (_SB_.PC00.PEG1.PEGP.XPS3, MethodObj)    // 0 Arguments

    Scope (\_SB.PC00.PEG1.PEGP)
    {
        Method (_PS3, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                If (CondRefOf (\_SB.PC00.PEG1.PEGP.NEGT))
                {
                    If ((OMPR == 0x03))
                    {
                        NEGT (Zero)
                    }
                }
            }

            If (CondRefOf (\_SB.PC00.PEG1.PEGP.XPS3))
            {
                XPS3 ()
            }
        }

        Method (_PS0, 0, NotSerialized)
        {
            If (CondRefOf (\_SB.PC00.PEG1.PEGP.XPS0))
            {
                XPS0 ()
            }

            If (_OSI ("Darwin"))
            {
                If (CondRefOf (\_SB.PC00.PEG1.PEGP.NEGT))
                {
                    NEGT (One)
                }
            }
        }
    }
}
