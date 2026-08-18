#cs ----------------------------------------------------------------------------

 AutoIt Version: 3.3.14.5
 Author:         Li Jin <lijin@redhat.com>
 Script Function:
	Driver File Signature Verification (sigverif.exe): Start scan, dismiss
	result dialog, close. Used by functest driver_sigverif (KAR win_sigverif).
	Optional $CmdLine[1] is the scan timeout in seconds (default 900).
#ce ----------------------------------------------------------------------------

Local $scanTimeout = 900
If $CmdLine[0] >= 1 Then
    $scanTimeout = Number($CmdLine[1])
    If $scanTimeout < 1 Then $scanTimeout = 900
EndIf

Run("sigverif.exe")
WinWaitActive("File Signature Verification", "&Start")
Send("!s")
if WinWaitActive("SigVerif", "Your files have been scanned and verified as digitally signed.", $scanTimeout) then
    Send("{ENTER}")
else
    Send("!c")
endif
WinWaitActive("File Signature Verification", "&Start")
Send("!c")
