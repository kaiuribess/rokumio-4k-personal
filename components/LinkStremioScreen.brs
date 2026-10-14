' LinkStremioScreen — displays the link-code pairing UI.
'
' Observes the LinkStremioTask's qrcode/link fields to show the pairing info, and
' the result field to detect completion or failure. A spinner covers the create
' call, then a centered column appears the moment the scan URL is known — with
' the two instruction steps, a "Press OK to get a new code" hint and a countdown
' to the pairing deadline. The QR is NOT what reveals the screen: it loads into
' the already-visible column and fills in when it arrives, or is replaced by
' "QR code unavailable — use the link below" if it fails, so a slow or broken
' image can never hide the link the user can type by hand. OK on the revealed
' column asks MainScene to restart the flow, which swaps in a fresh task; this
' screen re-binds through the taskNode field observer. Back publishes a
' cancelLogin; MainScene cancels the task and pops to AuthScreen.

sub init()
    m.PAIR_LIFETIME_SECONDS = 300
    m.STEP1_PREFIX = "1 - Scan the QR above or go to "
    m.titleLabel = m.top.FindNode("pairTitle")
    m.qrPoster = m.top.FindNode("pairQr")
    m.qrFallback = m.top.FindNode("pairQrFallback")
    m.column = m.top.FindNode("pairColumn")
    m.spinner = m.top.FindNode("pairSpinner")
    m.step1Label = m.top.FindNode("pairStep1Line")
    m.timerLabel = m.top.FindNode("pairTimer")
    m.statusLabel = m.top.FindNode("pairStatus")
    m.ticker = m.top.FindNode("pairTicker")

    t = Theme()
    m.titleLabel.color = t.accent
    m.qrFallback.color = t.textSecondary
    m.step1Label.drawingStyles = {
        default: { fontUri: "font:MediumSystemFont", color: t.textWhite }
        link: { fontUri: "font:MediumSystemFont", color: t.accent }
    }
    m.top.FindNode("pairStep2").color = t.textWhite
    m.timerLabel.color = t.textSecondary
    m.top.FindNode("pairRefreshHint").color = t.accent
    m.statusLabel.color = t.textSecondary

    ' The screen group itself takes focus at push (all its focusable children
    ' start inside the hidden column), which puts this subtree in the Roku focus
    ' chain. Without it, the push-time SetFocus cascade finds nothing focusable
    ' and the later button SetFocus after Reveal is silently dropped.
    m.top.focusable = true

    m.taskNode = invalid
    m.currentLink = invalid
    m.countdownSeconds = 0
    m.refreshing = false

    m.ticker.ObserveField("fire", "onTickerFire")
    m.top.ObserveField("taskNode", "onTaskNodeChanged")
end sub

function OnEnter(params as object) as void
    BindTask(m.top.taskNode)
end function

function OnExit() as void
    m.ticker.control = "stop"
end function

function OnBackPressed() as boolean
    m.top.pushRequest = { action: "cancelLogin" }
    return true
end function

sub BlurFocus()
end sub

' (Re)attach to a pairing task, resetting the UI to its loading pose. Rebinds
' safely: the previous task node's observers are dropped first so a stale worker
' can never write into this screen after a refresh. Task-written results are
' re-read so a task that settled before this screen started observing still
' lands on screen.
sub BindTask(task as object)
    if m.taskNode <> invalid then UnbindTask()
    m.taskNode = task
    if m.taskNode = invalid then return

    ResetUI()
    m.taskNode.ObserveField("link", "onTaskLink")
    m.taskNode.ObserveField("qrcode", "onTaskQrcode")
    m.taskNode.ObserveField("result", "onTaskResult")


    if m.taskNode.link <> invalid and m.taskNode.link <> "" and m.currentLink <> m.taskNode.link
        ShowLink(m.taskNode.link)
    end if
    if m.taskNode.qrcode <> invalid and m.taskNode.qrcode <> "" and m.qrPoster.uri <> m.taskNode.qrcode
        ShowQr(m.taskNode.qrcode)
    end if
    result = m.taskNode.result
    if result <> invalid then onTaskResult()
end sub

sub UnbindTask()
    if m.taskNode = invalid then return
    m.taskNode.UnobserveField("link")
    m.taskNode.UnobserveField("qrcode")
    m.taskNode.UnobserveField("result")
end sub

' MainScene swapped in a fresh task (refresh or initial). Rebinding resets the
' spinner/column to the loading pose and restarts the 5-minute countdown, so a
' requested new code shows a fresh UI with a clean clock.
sub onTaskNodeChanged()
    m.refreshing = false
    BindTask(m.top.taskNode)
end sub

' Back to the "fetching the QR" pose: spinner up, column down, countdown armed.
sub ResetUI()
    m.refreshing = false
    m.spinner.visible = true
    m.column.visible = false
    m.qrPoster.uri = ""
    ' onQrLoadStatus hides the poster when an image fails. ResetUI has to put it
    ' back: without this, one failed fetch left the poster hidden for the rest of
    ' the session, so "Request new code" could never show a QR again — the
    ' fallback text stayed up permanently even once a good code arrived.
    m.qrPoster.visible = true
    m.qrFallback.visible = false
    m.currentLink = invalid
    m.step1Label.text = m.STEP1_PREFIX
    m.statusLabel.text = "..."
    m.timerLabel.visible = true
    StopCountdown()
end sub

sub onTaskLink()
    if m.taskNode = invalid then return
    link = m.taskNode.link
    if link = invalid or link = "" then link = "https://link.stremio.com"
    ShowLink(link)
end sub

sub ShowLink(link as string)
    if m.currentLink = link then return
    m.currentLink = link
    ' The scan URL tags <link> (accent green) inside the white step1 prefix; the
    ' two are one MultiStyleLabel line, so they stay glued as the URL changes.
    m.step1Label.text = m.STEP1_PREFIX + "<link>" + link + "</link>"
    ' The link is what the user needs; the QR is an enhancement on top of it.
    ' Reveal on the link and start the pairing clock here, NOT when the PNG
    ' lands: the whole screen used to stay behind a spinner until a network
    ' image resolved, so a slow or stuck QR fetch meant no code, no URL and no
    ' way out but Back. The poster still fills in when it loads, and still falls
    ' back to text when it cannot.
    Reveal()
    StartCountdown()
end sub

sub onTaskQrcode()
    if m.taskNode = invalid then return
    qrcode = m.taskNode.qrcode
    if qrcode <> invalid and qrcode <> ""
        ShowQr(qrcode)
    end if
end sub

sub ShowQr(url as string)
    m.qrPoster.uri = url
    m.qrPoster.ObserveField("loadStatus", "onQrLoadStatus")
    ' A task that settled before this screen started observing will not fire the
    ' observer again, so read the current status too.
    ' Poster.loadStatus is none / loading / ready / failed, per the Poster field
    ' reference. "ready" is the success value. This screen used to compare
    ' against "loaded", which is not one of the documented values, so neither
    ' branch ever matched and the QR only ever appeared because the poster is
    ' visible by default — the failure path below had never actually run.
    status = m.qrPoster.loadStatus
    if status = "ready" or status = "failed" then onQrLoadStatus()
end sub

' The QR image finished loading or failing — swap the poster for the fallback
' text. This no longer reveals anything or touches the clock: ShowLink owns both
' now, so the image is purely a decoration and cannot hold the screen hostage.
' A ready QR paints; a failure swaps in the text the user can actually read.
sub onQrLoadStatus()
    status = m.qrPoster.loadStatus
    if status = "failed"
        m.qrPoster.visible = false
        m.qrFallback.visible = true
    else if status = "ready"
        m.qrPoster.visible = true
        m.qrFallback.visible = false
    end if
end sub

' Swap the spinner for the column. Idempotent — callers (QR ready, QR failure,
' settled task result) may race; the first one wins.
sub Reveal()
    if m.column.visible then return
    m.spinner.visible = false
    m.column.visible = true
end sub

' A nested Button never gets native OK delivery in this architecture (screen
' Groups visible-toggled under the Scene; Roku forum "Button Nested In Group Does
' Not Receive buttonSelected") — OK bubbles straight up the focus chain. So the
' refresh is handled here by key alone: OK on the revealed column (the "Press OK
' to get a new code" hint) triggers onRefreshSelected. The screen group holds the
' actual focus (m.top.focusable) so this handler receives the press; while the
' spinner covers the column OK is ignored, and Back is the Scene's.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "OK" and m.column.visible
        onRefreshSelected()
        return true
    end if
    return false
end function

' Every second, tick the countdown toward the pairing deadline. The create API
' exposes no server expiry, so the countdown targets the task's own read-poll
' window — the moment it stops checking and reports "Login timed out".
sub StartCountdown()
    m.countdownSeconds = m.PAIR_LIFETIME_SECONDS
    UpdateTimerLabel()
    m.ticker.control = "start"
end sub

sub StopCountdown()
    m.ticker.control = "stop"
end sub

sub onTickerFire()
    m.countdownSeconds = m.countdownSeconds - 1
    if m.countdownSeconds <= 0
        m.countdownSeconds = 0
        StopCountdown()
    end if
    UpdateTimerLabel()
end sub

sub UpdateTimerLabel()
    minutes = Int(m.countdownSeconds / 60)
    seconds = m.countdownSeconds mod 60
    m.timerLabel.text = "Code expires in " + minutes.ToStr() + ":" + Pad2(seconds)
end sub

function Pad2(value as integer) as string
    if value < 10 then return "0" + value.ToStr()
    return value.ToStr()
end function

' Request a fresh code: the Scene clears the old task and swaps in a new one,
' which flows back through onTaskNodeChanged. Guarded so rapid OK presses can't
' stack a burst of refreshes.
sub onRefreshSelected()
    if m.refreshing then return
    m.refreshing = true
    m.top.pushRequest = { action: "refreshCode" }
end sub

sub onTaskResult()
    if m.taskNode = invalid then return
    result = m.taskNode.result
    if result = invalid then return
    if result.ok
        StopCountdown()
        Reveal()
        m.statusLabel.text = "Logged in!"
        m.top.pushRequest = { action: "completeLogin", authKey: result.authKey, user: result.user }
    else
        ' Failure stays on screen so the user can read the error; Back is the
        ' exit (it publishes cancelLogin) and the refresh button offers a fresh
        ' code. A transient network hiccup must not boot the user off the
        ' pairing screen. No countdown — there is no code to expire.
        msg = result.error
        if msg = invalid or msg = "" then msg = "Login failed"
        StopCountdown()
        m.timerLabel.visible = false
        Reveal()
        m.statusLabel.text = msg
    end if
end sub
