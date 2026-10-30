#NoTrayIcon
#include <FileConstants.au3>

Opt("WinTitleMatchMode", 3)

Global Const $g_sDirectory = "C:\AutoHCK\SecureBootManual"
Global Const $g_sRequestPath = $g_sDirectory & "\request.json"
Global Const $g_sAckPath = $g_sDirectory & "\ack.json"
Global Const $g_sRoundPath = $g_sDirectory & "\round_id.txt"
Global Const $g_sLogPath = $g_sDirectory & "\watcher.log"
Global Const $g_sPrepareScript = "C:\UIAgent\autoit\prepare_secure_boot_ufds.ps1"
Global Const $g_sPrepareAttemptPath = $g_sDirectory & "\prepare_attempted.txt"
Global Const $g_sChangeUfd2Script = "C:\UIAgent\autoit\change_secure_boot_ufd2.ps1"
; Accept both reported HLK working-directory layouts; preserve the popup path.
Global Const $g_sZipPattern = '(?i)C:\\HLK\\(?:JobsWorkingDir|Jobs\\WorkingDir)\\Tasks\\[A-Za-z0-9_-]+\\UefiSecureBootManualTests\.zip'
Global $g_iSequence = 0
Global $g_hHandledWindow = 0
Global $g_sHandledTitle = ""
Global $g_sHandledText = ""

DirCreate($g_sDirectory)
OnAutoItExitRegister("LogWatcherExit")
LogMessage("Secure Boot manual watcher started; script=" & @ScriptFullPath)

While 1
    ; Do not handle the same popup twice after attempting its button click.
    If $g_hHandledWindow <> 0 Then
        If Not WinExists($g_hHandledWindow) Or WinGetTitle($g_hHandledWindow) <> $g_sHandledTitle Or _
                WinGetText($g_hHandledWindow) <> $g_sHandledText Then
            $g_hHandledWindow = 0
            $g_sHandledTitle = ""
            $g_sHandledText = ""
        EndIf
    EndIf

    If $g_hHandledWindow = 0 Then
        PollPopups()
    EndIf

    Sleep(250)
WEnd

Func PollPopups()
    Local $hBootOrder = WinGetHandle("Trigger reboot to configure BIOS boot order?")
    If $hBootOrder <> 0 Then
        If ExpectedPopup($hBootOrder, "CONFIGURE_BOOT_ORDER") Then
            SkipBootOrderReboot($hBootOrder)
            Return
        EndIf
    EndIf

    Local $hPrepare = WinGetHandle("Prepare USB Flash Drives")
    If $hPrepare <> 0 Then
        If ExpectedPopup($hPrepare, "PREPARE_UFDS") Then
            PrepareUfds($hPrepare)
            Return
        EndIf
    EndIf

    Local $hChangeUfd2 = WinGetHandle("Change UFD #2 to use msft_test_pressanykey.efi")
    If $hChangeUfd2 <> 0 Then
        If ExpectedPopup($hChangeUfd2, "CHANGE_UFD2_TO_MSFT_TEST") Then
            ChangeUfd2($hChangeUfd2)
            Return
        EndIf
    EndIf

    ; HLK uses "from" for the first UFD #1 round and "into" in later rounds.
    Local $aUfd1Titles = ["Insert and boot from UFD #1", "Insert and boot into UFD #1"]
    For $sUfd1Title In $aUfd1Titles
        Local $hUfd1 = WinGetHandle($sUfd1Title)
        If $hUfd1 <> 0 Then
            If ExpectedPopup($hUfd1, "REQUEST_UFD1") Then
                HandlePopup($hUfd1, "REQUEST_UFD1")
                Return
            EndIf
        EndIf
    Next

    Local $hUfd2 = WinGetHandle("Insert and boot into UFD #2")
    If $hUfd2 <> 0 Then
        If ExpectedPopup($hUfd2, "REQUEST_UFD2") Then
            HandlePopup($hUfd2, "REQUEST_UFD2")
            Return
        EndIf
    EndIf

    Local $aResults = ["RESULT_UFD1", "RESULT_UFD2", "RESULT_MSFT"]
    For $sResult In $aResults
        Local $hResult = WinGetHandle(ResultTitle($sResult))
        If $hResult <> 0 Then
            If ExpectedPopup($hResult, $sResult) Then
                HandlePopup($hResult, $sResult)
            Else
                LogMessage("Unrecognized result question/buttons; leaving unanswered: " & WinGetText($hResult))
                MarkHandled($hResult)
            EndIf
            Return
        EndIf
    Next

    Local $hFinished = WinGetHandle("Finished Test")
    If $hFinished <> 0 Then
        If ExpectedPopup($hFinished, "FINISHED_TEST") Then
            AcknowledgeFinishedTest($hFinished)
            Return
        EndIf
    EndIf
EndFunc

Func ExpectedPopup($hWindow, $sEvent)
    If ResultTitle($sEvent) <> "" Then
        Return WinGetTitle($hWindow) == ResultTitle($sEvent) And _
                ResultQuestion($hWindow) == ExpectedQuestion($sEvent) And _
                ResultButton($hWindow, "Yes") <> 0 And ResultButton($hWindow, "No") <> 0
    EndIf
    ; These distinct insertion titles identify the requested UFD. Do not read
    ; or match their body text, including when rechecking before the ACK click.
    ; Require the same OK control that HandlePopup uses after acknowledgement.
    If $sEvent = "REQUEST_UFD1" Then
        Local $sUfd1Title = WinGetTitle($hWindow)
        Return ($sUfd1Title == "Insert and boot from UFD #1" Or _
                $sUfd1Title == "Insert and boot into UFD #1") And _
                ControlGetHandle($hWindow, "", "[CLASS:Button; TEXT:OK]") <> 0
    EndIf

    If $sEvent = "REQUEST_UFD2" Then
        Local $sTitle = WinGetTitle($hWindow)
        Local $hOk = ControlGetHandle($hWindow, "", "[CLASS:Button; TEXT:OK]")
        Local $bMatches = $sTitle == "Insert and boot into UFD #2" And $hOk <> 0
        Return $bMatches
    EndIf

    Local $sText = WinGetText($hWindow)
    If $sEvent = "FINISHED_TEST" Then
        ; Ignore line wrapping and OK captions, but require the full notice.
        Local $sFinishedText = StringStripWS(StringRegExpReplace($sText, "\s+", " "), 3)
        $sFinishedText = StringRegExpReplace($sFinishedText, '^(?:&?OK\s+)+', '')
        $sFinishedText = StringRegExpReplace($sFinishedText, '(?:\s+&?OK)+$', '')
        Local $sFinishedBody = "If you want to run other Secure Boot Logo tests then go into the BIOS " & _
                "Configuration and restore Secure Boot to the default configuration."
        Return WinGetTitle($hWindow) == "Finished Test" And $sFinishedText == $sFinishedBody
    EndIf

    If $sEvent = "CONFIGURE_BOOT_ORDER" Then
        ; WinGetText also includes button captions. Match the entire supplied
        ; body within it, allowing only whitespace/line-wrapping differences.
        Local $sBootOrderText = StringRegExpReplace($sText, "\s+", " ")
        Local $sExpectedBody = "In order to proceed with this test, the BIOS must be " & _
                "configured to have EFI USB as the first option in the boot order. " & _
                "Click YES to trigger a reboot so that you can update the BIOS configuration. " & _
                "Click NO if EFI USB is already the first option in the boot order. " & _
                'Note: The BIOS entry for EFI USB may have a different name such as "USB HDD"'
        Return WinGetTitle($hWindow) == "Trigger reboot to configure BIOS boot order?" And _
                StringInStr($sBootOrderText, $sExpectedBody, 1) > 0
    EndIf

    If $sEvent = "CHANGE_UFD2_TO_MSFT_TEST" Then
        Local $sNormalized = StringRegExpReplace($sText, "\s+", " ")
        Return WinGetTitle($hWindow) = "Change UFD #2 to use msft_test_pressanykey.efi" And _
                StringInStr($sNormalized, "On UFD #2, delete or move the current") > 0 And _
                StringInStr($sNormalized, "efi\boot\boot<arch>.efi") > 0 And _
                StringInStr($sNormalized, "Rename") > 0 And _
                StringInStr($sNormalized, "efi\boot\msft_test_pressanykey.efi") > 0 And _
                StringInStr($sNormalized, "boot from UFD #2") > 0
    EndIf

    If $sEvent = "PREPARE_UFDS" Then
        ; Match filenames and the dynamic ZIP path, not line breaks or the
        ; whole body. WinGetText may also include OK and Cancel captions.
        Return WinGetTitle($hWindow) = "Prepare USB Flash Drives" And _
                StringInStr($sText, "pressanykey1.efi") > 0 And _
                StringInStr($sText, "pressanykey2.efi") > 0 And _
                StringInStr($sText, "msft_test_pressanykey.efi") > 0 And _
                ExtractZipPath($sText) <> ""
    EndIf

    Return False
EndFunc

Func AcknowledgeFinishedTest($hWindow)
    ; Dismiss the final notice only. Do not restore firmware keys or assert
    ; a test result: HLK determines the outcome after this acknowledgement.
    If Not ExpectedPopup($hWindow, "FINISHED_TEST") Then Return
    Local $hOk = ControlGetHandle($hWindow, "", "[CLASS:Button; TEXT:OK]")
    If $hOk = 0 Then $hOk = ControlGetHandle($hWindow, "", "[CLASS:Button; TEXT:&OK]")
    If $hOk = 0 Then
        LogMessage("Finished Test popup matched, but OK control was not found; leaving popup open")
        MarkHandled($hWindow)
        Return
    EndIf

    WinActivate($hWindow)
    If Not ExpectedPopup($hWindow, "FINISHED_TEST") Then Return
    MarkHandled($hWindow)
    LogMessage("Finished Test popup matched; clicking OK")
    If ControlClick($hWindow, "", $hOk) Then
        LogMessage("Clicked OK on Finished Test popup; Secure Boot configuration unchanged")
    Else
        LogMessage("Finished Test popup matched, but OK control was not clickable; leaving popup open")
    EndIf
EndFunc

Func SkipBootOrderReboot($hWindow)
    ; This is a guest-only acknowledgement, not a UFD selection request.
    ; The insertion prompts select the requested UFD via runtime bootindex.
    If Not ExpectedPopup($hWindow, "CONFIGURE_BOOT_ORDER") Then Return
    Local $hNo = ControlGetHandle($hWindow, "", "[CLASS:Button; TEXT:No]")
    If $hNo = 0 Then $hNo = ControlGetHandle($hWindow, "", "[CLASS:Button; TEXT:&No]")
    If $hNo = 0 Then
        LogMessage("Boot-order popup matched, but No control was not found; leaving popup open")
        MarkHandled($hWindow)
        Return
    EndIf

    WinActivate($hWindow)
    If Not ExpectedPopup($hWindow, "CONFIGURE_BOOT_ORDER") Then Return
    MarkHandled($hWindow)
    LogMessage("Boot-order popup matched; clicking No")
    If ControlClick($hWindow, "", $hNo) Then
        LogMessage("Clicked No on boot-order popup; UFD selection uses runtime bootindex")
    Else
        LogMessage("Boot-order popup matched, but No control was not clickable; leaving popup open")
    EndIf
EndFunc

Func ExtractZipPath($sText)
    ; Restrict the dynamic task directory to one path component. The guest
    ; PowerShell script also validates the path before using it.
    Local $aPaths = StringRegExp($sText, $g_sZipPattern, 3)
    If @error Then Return ""
    If UBound($aPaths) <> 1 Then Return ""
    Return $aPaths[0]
EndFunc

Func PrepareUfds($hWindow)
    LogMessage("PREPARE_UFDS matched; checking prerequisites")
    Local $sZipPath = ExtractZipPath(WinGetText($hWindow))
    If $sZipPath = "" Or Not FileExists($g_sPrepareScript) Then
        LogMessage("Cannot prepare UFDs: missing HLK ZIP path or guest preparation script")
        MarkHandled($hWindow)
        Return
    EndIf
    If Not IsAdmin() Then
        LogMessage("Cannot prepare UFDs: watcher is not elevated")
        MarkHandled($hWindow)
        Return
    EndIf
    If FileExists($g_sPrepareAttemptPath) Then
        LogMessage("UFD preparation was already attempted; leaving popup open for manual inspection")
        MarkHandled($hWindow)
        Return
    EndIf

    ; Persist this marker before starting the destructive format. A watcher
    ; restart must not automatically retry a partially completed preparation.
    Local $hMarker = FileOpen($g_sPrepareAttemptPath, $FO_OVERWRITE + $FO_UTF8_NOBOM)
    If $hMarker = -1 Then
        LogMessage("Cannot record UFD preparation attempt")
        MarkHandled($hWindow)
        Return
    EndIf
    Local $bWritten = FileWrite($hMarker, $sZipPath)
    FileClose($hMarker)
    If Not $bWritten Then
        LogMessage("Cannot record UFD preparation attempt")
        MarkHandled($hWindow)
        Return
    EndIf

    Local $sPowerShell = @WindowsDir & "\System32\WindowsPowerShell\v1.0\powershell.exe"
    Local $sCommand = '"' & $sPowerShell & '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' & _
            $g_sPrepareScript & '" -ZipPath "' & $sZipPath & '"'
    LogMessage("Preparing UFDs locally from " & $sZipPath)
    Local $iExitCode = RunWait($sCommand, "", @SW_HIDE)
    Local $iRunError = @error
    If $iRunError Or $iExitCode <> 0 Then
        LogMessage("UFD preparation failed (RunWait error=" & $iRunError & ", exit=" & $iExitCode & "); see prepare.log")
        MarkHandled($hWindow)
        Return
    EndIf

    If Not WinExists($hWindow) Or Not ExpectedPopup($hWindow, "PREPARE_UFDS") Or _
            ExtractZipPath(WinGetText($hWindow)) <> $sZipPath Then
        LogMessage("UFD preparation succeeded, but the original popup changed before OK")
        Return
    EndIf
    WinActivate($hWindow)
    MarkHandled($hWindow)
    LogMessage("UFD preparation verified; clicking OK")
    If ControlClick($hWindow, "", "[CLASS:Button; TEXT:OK]") Then
        LogMessage("Prepared UFDs and clicked OK")
    Else
        LogMessage("Prepared UFDs, but OK control was not clickable")
    EndIf
EndFunc

Func ChangeUfd2($hWindow)
    If Not FileExists($g_sChangeUfd2Script) Or Not IsAdmin() Then
        LogMessage("Cannot change UFD #2: missing guest script or watcher is not elevated")
        MarkHandled($hWindow)
        Return
    EndIf
    Local $sPopupText = WinGetText($hWindow)
    Local $sPowerShell = @WindowsDir & "\System32\WindowsPowerShell\v1.0\powershell.exe"
    Local $sCommand = '"' & $sPowerShell & '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' & _
            $g_sChangeUfd2Script & '"'
    LogMessage("Changing UFD #2 to use msft_test_pressanykey.efi locally")
    Local $iExitCode = RunWait($sCommand, "", @SW_HIDE)
    Local $iRunError = @error
    If $iRunError Or $iExitCode <> 0 Then
        LogMessage("UFD #2 file change failed (RunWait error=" & $iRunError & ", exit=" & $iExitCode & "); see change_ufd2.log")
        MarkHandled($hWindow)
        Return
    EndIf

    If Not WinExists($hWindow) Or Not ExpectedPopup($hWindow, "CHANGE_UFD2_TO_MSFT_TEST") Or _
            WinGetText($hWindow) <> $sPopupText Then
        LogMessage("UFD #2 file change succeeded, but the original popup changed before OK")
        Return
    EndIf
    ; This popup can reboot directly, without another insertion prompt. Arm
    ; its own serial observation and select UFD2 before acknowledging it.
    LogMessage("UFD #2 file change verified; requesting boot selection and observation")
    HandlePopup($hWindow, "CHANGE_UFD2_TO_MSFT_TEST")
EndFunc

Func HandlePopup($hWindow, $sEvent)
    $g_iSequence += 1
    Local $sId = @YEAR & @MON & @MDAY & "_" & @HOUR & @MIN & @SEC & @MSEC & "_" & @AutoItPID & "_" & $g_iSequence
    Local $bResult = ResultTitle($sEvent) <> ""
    Local $sRoundId = ""
    Local $sQuestion = ""
    Local $sRequest = '{"id":"' & $sId & '","event":"' & $sEvent & '"'
    If $bResult Then
        $sRoundId = StringStripWS(FileRead($g_sRoundPath), 3)
        If Not StringRegExp($sRoundId, '^[a-zA-Z0-9_-]{1,80}$') Then
            LogMessage("Result has no valid persisted boot-round ID; leaving unanswered")
            MarkHandled($hWindow)
            Return
        EndIf
        $sQuestion = ResultQuestion($hWindow)
        $sRequest &= ',"round_id":' & JsonString($sRoundId) & ',"title":' & JsonString(WinGetTitle($hWindow)) & _
                ',"question":' & JsonString($sQuestion)
    EndIf
    $sRequest &= '}'
    Local $sExpectedAck = '{"id":"' & $sId & '","event":"' & $sEvent & '","status":"READY"}'
    Local $sTempPath = $g_sRequestPath & "." & $sId & ".tmp"

    LogMessage("Publishing " & $sEvent & ": id=" & $sId & "; hwnd=" & $hWindow & "; path=" & $g_sRequestPath)
    Local $hFile = FileOpen($sTempPath, $FO_OVERWRITE + $FO_UTF8_NOBOM)
    If $hFile = -1 Then
        LogMessage("Unable to create request file for " & $sEvent)
        MarkHandled($hWindow)
        Return
    EndIf
    Local $bWritten = FileWrite($hFile, $sRequest)
    FileClose($hFile)
    If Not $bWritten Or Not FileMove($sTempPath, $g_sRequestPath, $FC_OVERWRITE) Then
        LogMessage("Unable to publish request for " & $sEvent)
        FileDelete($sTempPath)
        MarkHandled($hWindow)
        Return
    EndIf

    LogMessage("Waiting for host acknowledgement: " & $sEvent & " (" & $sId & ")")
    While WinExists($hWindow) And ExpectedPopup($hWindow, $sEvent)
        Local $sAck = FileRead($g_sAckPath)
        Local $sButton = ""
        If $bResult Then
            Local $aAnswers = ["Yes", "No"]
            For $sAnswer In $aAnswers
                Local $sResultAck = '{"id":"' & $sId & '","event":"' & $sEvent & '","status":"READY",' & _
                        '"round_id":' & JsonString($sRoundId) & ',"question":' & JsonString($sQuestion) & _
                        ',"answer":' & JsonString($sAnswer) & '}'
                If $sAck == $sResultAck Then $sButton = $sAnswer
            Next
        ElseIf $sAck == $sExpectedAck Then
            $sButton = "OK"
        EndIf
        If $sButton <> "" Then
            ; Recheck the exact question as well as its title before acting.
            If Not WinExists($hWindow) Or Not ExpectedPopup($hWindow, $sEvent) Then ExitLoop
            If Not $bResult Then
                ; Persist before the click can reboot Windows and this watcher.
                If Not SaveRoundId($sId) Then
                    LogMessage("Cannot persist boot-round ID; leaving popup open")
                    MarkHandled($hWindow)
                    Return
                EndIf
            EndIf
            WinActivate($hWindow)
            ; Capture the original popup before the click can open the next one.
            ; Keep it guarded on failure for manual inspection.
            MarkHandled($hWindow)
            LogMessage("Host acknowledged " & $sEvent & "; clicking " & $sButton & " (" & $sId & ")")
            Local $hButton = ControlGetHandle($hWindow, "", "[CLASS:Button; TEXT:OK]")
            If $bResult Then $hButton = ResultButton($hWindow, $sButton)
            If $hButton <> 0 And ControlClick($hWindow, "", $hButton) Then
                LogMessage("Clicked " & $sButton & " after host acknowledged " & $sEvent & " (" & $sId & ")")
            Else
                LogMessage("Host acknowledged " & $sEvent & " but " & $sButton & " control was not clickable")
            EndIf
            Return
        EndIf
        Sleep(250)
    WEnd

    ; The operator may have closed the dialog before the host replied.
    ; Remove only this request, leaving any newer request untouched.
    If FileExists($g_sRequestPath) And FileRead($g_sRequestPath) = $sRequest Then FileDelete($g_sRequestPath)
    LogMessage("Popup closed before acknowledgement: " & $sEvent & " (" & $sId & ")")
EndFunc

Func ResultTitle($sEvent)
    Switch $sEvent
        Case "RESULT_UFD1"
            Return "UFD #1 Boot Result"
        Case "RESULT_UFD2"
            Return "UFD #2 Boot Result"
        Case "RESULT_MSFT"
            Return "UFD Test App Boot Result"
    EndSwitch
    Return ""
EndFunc

Func ExpectedQuestion($sEvent)
    Switch $sEvent
        Case "RESULT_UFD1"
            Return 'Did UFD #1 boot and display "** 1 ** pressanykey1.efi"?'
        Case "RESULT_UFD2"
            Return 'Did UFD #2 boot and display "** 2 ** pressanykey2.efi"?'
        Case "RESULT_MSFT"
            Return 'Did UFD boot and display "** TEST ** msft_test_pressanykey.efi"?'
    EndSwitch
    Return ""
EndFunc

Func ResultQuestion($hWindow)
    ; WinGetText includes button captions. Remove ONLY Yes/No captions at the
    ; edges; the entire remaining question must match (including quotes).
    Local $sText = StringStripWS(StringRegExpReplace(WinGetText($hWindow), '\s+', ' '), 3)
    $sText = StringRegExpReplace($sText, '^(?:&?(?:Yes|No)\s+)+', '')
    Return StringRegExpReplace($sText, '(?:\s+&?(?:Yes|No))+$', '')
EndFunc

Func ResultButton($hWindow, $sAnswer)
    Local $hButton = ControlGetHandle($hWindow, "", "[CLASS:Button; TEXT:" & $sAnswer & "]")
    If $hButton = 0 Then $hButton = ControlGetHandle($hWindow, "", "[CLASS:Button; TEXT:&" & $sAnswer & "]")
    Return $hButton
EndFunc

Func SaveRoundId($sId)
    Local $hFile = FileOpen($g_sRoundPath & ".tmp", $FO_OVERWRITE + $FO_UTF8_NOBOM)
    If $hFile = -1 Then Return False
    Local $bWritten = FileWrite($hFile, $sId)
    FileClose($hFile)
    Return $bWritten And FileMove($g_sRoundPath & ".tmp", $g_sRoundPath, $FC_OVERWRITE)
EndFunc

Func JsonString($sValue)
    Local $sEscaped = StringReplace($sValue, '\', '\\')
    $sEscaped = StringReplace($sEscaped, '"', '\"')
    $sEscaped = StringReplace($sEscaped, @CR, '\r')
    $sEscaped = StringReplace($sEscaped, @LF, '\n')
    Return '"' & $sEscaped & '"'
EndFunc

Func MarkHandled($hWindow)
    ; Call before clicking: HLK may reuse the window for the next popup.
    $g_hHandledWindow = $hWindow
    $g_sHandledTitle = WinGetTitle($hWindow)
    $g_sHandledText = WinGetText($hWindow)
EndFunc

Func LogWatcherExit()
    LogMessage("Secure Boot manual watcher stopped; exit_method=" & @exitMethod & "; exit_code=" & @exitCode)
EndFunc

Func LogMessage($sMessage)
    FileWrite($g_sLogPath, "[" & @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC & _
            "] [PID=" & @AutoItPID & "] " & $sMessage & @CRLF)
EndFunc
