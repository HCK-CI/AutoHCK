#cs ----------------------------------------------------------------------------

 AutoIt Version: 3.3.14.5
 Author:         Li Jin <lijin@redhat.com>
 Script Function:
	Drive File Signature Verification (sigverif.exe): Start scan, dismiss
	result dialog, close. Used by functest driver_sigverif (KAR win_sigverif).
#ce ----------------------------------------------------------------------------

Run("sigverif.exe")
WinWaitActive("File Signature Verification", "&Start")
Send("!s")
if WinWaitActive("SigVerif", "Your files have been scanned and verified as digitally signed.", 60) then
    Send("{ENTER}")
else
    Send("!c")
endif
WinWaitActive("File Signature Verification", "&Start")
Send("!c")
