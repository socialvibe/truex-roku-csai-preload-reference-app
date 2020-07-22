' Copyright (c) 2019 true[X], Inc. All rights reserved.
'-----------------------------------------------------------------------------------------------------------
' ContentFlow
'-----------------------------------------------------------------------------------------------------------
'
' NOTE: Expects m.global.streamInfo to exist with the necessary video stream information.
'
' Member Variables:
'   * videoPlayer as Video - the video player that plays the content stream
'   * adRenderer as TruexAdRenderer - instance of the true[X] renderer, used to present true[X] ads
'-----------------------------------------------------------------------------------------------------------

sub init()
    ? "TRUE[X] >>> ContentFlow::init()"

    ' streamInfo must be provided by the global node before instantiating ContentFlow
    if not unpackStreamInformation() then return

    ' get reference to video player
    m.videoPlayer = m.top.findNode("videoPlayer")

    ? "TRUE[X] >>> ContentFlow::init() - starting video stream=";m.streamData;"..."
    beginStream(m.streamData.url)
end sub

'-------------------------------------------
' Currently does not handle any key events.
'-------------------------------------------
function onKeyEvent(key as string, press as boolean) as boolean
    ? "TRUE[X] >>> ContentFlow::onKeyEvent(key=";key;" press=";press.ToStr();")"
    if press and key = "back" and m.adRenderer = invalid then
        ? "TRUE[X] >>> ContentFlow::onKeyEvent() - back pressed while content is playing, requesting stream cancel..."
        tearDown()
        m.top.event = { trigger: "cancelStream" }
    end if
    return press
end function

'------------------------------------------------------------------------------------------------
' Callback triggered when TruexAdRenderer updates its 'event' field.
'
' The following event types are supported:
'   * adFreePod - user has met engagement requirements, skips past remaining pod ads
'   * adStarted - user has started their ad engagement
'   * adFetchCompleted - TruexAdRenderer received ad fetch response
'   * optOut - user has opted out of true[X] engagement, show standard ads
'   * optIn - this event is triggered when a user decides opt-in to the true[X] interactive ad
'   * adCompleted - user has finished the true[X] engagement, resume the video stream
'   * adError - TruexAdRenderer encountered an error presenting the ad, resume with standard ads
'   * noAdsAvailable - TruexAdRenderer has no ads ready to present, resume with standard ads
'   * userCancel - This event will fire when a user backs out of the true[X] interactive ad unit after having opted in.
'   * userCancelStream - user has requested the video stream be stopped
'
' Params:
'   * event as roAssociativeArray - contains the TruexAdRenderer event data
'------------------------------------------------------------------------------------------------
sub onTruexEvent(event as object)
    ? "TRUE[X] >>> ContentFlow::onTruexEvent()"

    data = event.getData()
    if data = invalid then return else ? "TRUE[X] >>> ContentFlow::onTruexEvent(eventData=";data;")"

    if data.type = "adFreePod" then
        ' this event is triggered when a user has completed all the true[X] engagement criteria
        ' this entails interacting with the true[X] ad and viewing it for X seconds (usually 30s)
        ' user has earned credit for the engagement, set seek duration to skip the entire ad break
        m.streamSeekDuration = m.streamSeekDuration + m.currentAdBreak.videoAdDuration
    else if data.type = "adStarted" then
        ' this event is triggered when the true[X] Choice Card is presented to the user
    else if data.type = "adFetchCompleted" then
        ' this event is triggered when TruexAdRenderer receives a response to an ad fetch request
    else if data.type = "optOut" then
        ' this event is triggered when a user decides not to view a true[X] interactive ad
        ' that means the user was presented with a Choice Card and opted to watch standard video ads
        if not data.userInitiated then
            m.skipSeek = true
        end if
    else if data.type = "optIn" then
        ' this event is triggered when a user decides opt-in to the true[X] interactive ad
        m.videoPlayer.control = "stop"
    else if data.type = "adCompleted" then
        ' this event is triggered when TruexAdRenderer is done presenting the ad
        ' if the user earned credit (via "adFreePod") their content will already be seeked past the ad break
        ' if the user has not earned credit their content will resume at the beginning of the ad break
        resumeVideoStream()
    else if data.type = "adError" then
        ' this event is triggered whenever TruexAdRenderer encounters an error
        ' usually this means the video stream should continue with normal video ads
        resumeVideoStream()
    else if data.type = "noAdsAvailable" then
        ' this event is triggered when TruexAdRenderer receives no usable true[X] ad in the ad fetch response
        ' usually this means the video stream should continue with normal video ads
        resumeVideoStream()
    else if data.type = "userCancel" then
        ' This event will fire when a user backs out of the true[X] interactive ad unit after having opted in. 
        ' Here we need to seek back to the beginning of the true[X] video choice card asset
        m.streamSeekDuration = 0
        resumeVideoStream()
    else if data.type = "userCancelStream" then
        ' this event is triggered when the user performs an action interpreted as a request to end the video playback
        ' this event can be disabled by adding supportsUserCancelStream=false to the TruexAdRenderer init payload
        ' there are two circumstances where this occurs:
        '   1. The user was presented with a Choice Card and presses Back
        '   2. The user has earned an adFreePod and presses Back to exit engagement instead of Watch Your Show button
        ? "TRUE[X] >>> ContentFlow::onTruexEvent() - user requested video stream playback cancel..."
        tearDown()
        m.top.event = { trigger: "cancelStream" }
    end if
end sub

'--------------------------------------------------------------------------------------------------------
' Launches the true[X] renderer based on the current ad break as detected by onVideoPositionChange
'--------------------------------------------------------------------------------------------------------
sub launchTruexAd()
    ? "TRUE[X] >>> ContentFlow::onTruexAdDataReceived()"

    decodedData = m.currentAdBreak
    if decodedData = invalid then return

    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - starting ad at video position: ";m.videoPlayer.position

    ' Hedge against Roku playhead imprecision by adding buffer so that non choice card content is not shown
    m.videoPositionAtAdBreakPause = m.videoPlayer.position + 0.5
    ' Note: bumping the seek interval as the Roku player seems to have trouble seeking ahead to a specific time based on the type of stream.
    m.streamSeekDuration = decodedData.cardDuration + 3
    ' Populating the test ad from the local mock payload
    ' In a real world situation, the adParameters returned from the ad server will be populated similarly 
    ' for the One Stage type integration we're demonstrating here.
    adPayload = ParseJson(ReadAsciiFile(decodedData.vastPayload).trim())
    adPayload.placement_hash = decodedData.placementHash

    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - instantiating TruexAdRenderer ComponentLibrary..."

    ' instantiate TruexAdRenderer and register for event updates
    m.adRenderer = m.top.createChild("TruexLibrary:TruexAdRenderer")
    m.adRenderer.observeFieldScoped("event", "onTruexEvent")

    ' use the companion ad data to initialize the true[X] renderer
    tarInitAction = {
        type: "init",
        adParameters: adPayload,
        supportsUserCancelStream: true, ' enables cancelStream event types, disable if Channel does not support
        slotType: UCase(getCurrentAdBreakSlotType()),
        logLevel: 1, ' Optional parameter, set the verbosity of true[X] logging, from 0 (mute) to 5 (verbose), defaults to 5
        channelWidth: 1920, ' Optional parameter, set the width in pixels of the channel's interface, defaults to 1920
        channelHeight: 1080 ' Optional parameter, set the height in pixels of the channel's interface, defaults to 1080
    }
    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - initializing TruexAdRenderer with action=";tarInitAction
    m.adRenderer.action = tarInitAction

    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - starting TruexAdRenderer..."
    m.adRenderer.action = { type: "start" }
    m.adRenderer.focusable = true
    m.adRenderer.SetFocus(true)
end sub

'--------------------------------------------------------------------------------------------------------
' Callback triggered when the video player's playhead changes. Used to keep track of ad pods and 
' trigger the instantiation of the true[X] experience.
''--------------------------------------------------------------------------------------------------------
sub onVideoPositionChange()
    ' ? "TRUE[X] >>> ContentFlow::onVideoPositionChange: " + Str(m.videoPlayer.position) + " duration: " + Str(m.videoPlayer.duration)
    if m.vmap = invalid or m.vmap.Count() = 0 then return

    playheadInPod = false

    ' Check to see if playback has entered a true[X] spot, and if so, start true[X].
    for each vmapEntry in m.vmap
        if vmapEntry.startOffset <> invalid and vmapEntry.endOffset <> invalid then
            if m.videoPlayer.position >= vmapEntry.startOffset and m.videoPlayer.position <= vmapEntry.endOffset then
                if m.adRenderer = invalid
                    ? "TRUE[X] >>> ContentFlow::onVideoPositionChange: in pod: " ; vmapEntry.breakId
                    ? "TRUE[X] >>> ContentFlow::onVideoPositionChange: launching tag: " ; vmapEntry.vastUrl
                    m.currentAdBreak = vmapEntry
                    launchTruexAd()
                end if
                ' Do not allow video scrubbing while in the true[X] opt-in flow
                m.videoPlayer.enableTrickPlay = false
                playheadInPod = true
            else
                m.videoPlayer.enableTrickPlay = true
            end if
        end if 
    end for

    if m.adRenderer <> invalid and not playheadInPod then
        ? "TRUE[X] >>> ContentFlow::onVideoPositionChange: exiting pod, dismissing TAR"
        ' If we are not in a pod and TAR is active that is taken to mean playback has auto-advanced past the opt-in card 
        ' into the rest of the video ads without the viewer taking action to opt-in or out. 
        ' This scenario is known as an auto-advance opt-out (non user initiated opt-out)
        ' Therefore terminate TAR at this stage.
        m.adRenderer.action = { type : "stop" }
    end if

    m.lastVideoPosition = m.videoPlayer.position
end sub

'----------------------------------------------------------------------------------
' Constructs m.streamData from stream information provided at m.global.streamInfo.
'
' Return:
'   false if there was an error unpacking m.global.streamInfo, otherwise true
'----------------------------------------------------------------------------------
function unpackStreamInformation() as boolean
    if m.global.streamInfo = invalid then
        ? "TRUE[X] >>> ContentFlow::unpackStreamInformation() - invalid m.global.streamInfo, must be provided..."
        return false
    end if

    ' extract stream info JSON into associative array
    ? "TRUE[X] >>> ContentFlow::unpackStreamInformation() - parsing m.global.streamInfo=";m.global.streamInfo;"..."
    jsonStreamInfo = ParseJson(m.global.streamInfo)[0]
    if jsonStreamInfo = invalid then
        ? "TRUE[X] >>> ContentFlow::unpackStreamInformation() - could not parse streamInfo as JSON, aborting..."
        return false
    end if

    preprocessVmapData(jsonStreamInfo.vmap)

    ' define the test stream
    m.streamData = {
        title: jsonStreamInfo.title,
        url: jsonStreamInfo.url,
        vmap: jsonStreamInfo.vmap,
        type: "vod"
    }
    ? "TRUE[X] >>> ContentFlow::unpackStreamInformation() - streamData=";m.streamData

    return true
end function

'----------------------------------------------------------------------------------
' Parses out the configured stream playlist ad pods into data structures used at
' runtime. These pods are defined in the res/reference-app-streams.json and 
' emulate what would come down from an SSAI stack or ad server as the playlist
' of ads for the current stream.
'----------------------------------------------------------------------------------
sub preprocessVmapData(vmapJson as object)
    if vmapJson = invalid or Type(vmapJson) <> "roArray" return
    m.vmap = []

    for i = 0 to vmapJson.Count() - 1
        vmapEntry = vmapJson[i]
        timeOffset = vmapEntry.timeOffset
        duration = vmapEntry.cardDuration
        videoAdDuration = vmapEntry.videoAdDuration

        if timeOffset <> invalid and duration <> invalid then
            ' trim ms portion
            timeOffset = timeOffset.Left(8)
            timeOffsetComponents = timeOffset.Split(":")
            timeOffsetSecs = timeOffsetComponents[2].ToInt() + timeOffsetComponents[1].ToInt() * 60 + timeOffsetComponents[0].ToInt() * 3600
            timeOffsetEnd = timeOffsetSecs + duration.ToInt()
            ? "TRUE[X] >>> ContentFlow::preprocessVmapData, #" ; i + 1 ; ", timeOffset: "; timeOffset ; ", start: " ; timeOffsetSecs ; " end: " timeOffsetEnd
            vmapEntry.startOffset = timeOffsetSecs
            vmapEntry.endOffset = timeOffsetEnd
            vmapEntry.cardDuration = duration.ToInt()
            vmapEntry.videoAdDuration = videoAdDuration.ToInt()
            vmapEntry.podindex = i
            m.vmap.Push(vmapEntry)
        end if
    end for
end sub

'-----------------------------------------------------------------------------------
' Determines the current ad break's (m.currentAdBreak) slot type.
'
' Return:
'   invalid if m.currentAdBreak is not set, otherwise either "midroll" or "preroll"
'-----------------------------------------------------------------------------------
function getCurrentAdBreakSlotType() as dynamic
    if m.currentAdBreak = invalid then return invalid
    if m.currentAdBreak.podindex > 0 then return "midroll" else return "preroll"
end function

sub tearDown()
    destroyTruexAdRenderer()
    if m.videoPlayer <> invalid then m.videoPlayer.control = "stop"
end sub

sub destroyTruexAdRenderer()
    if m.adRenderer <> invalid then
        m.adRenderer.SetFocus(false)
        m.top.removeChild(m.adRenderer)
        m.adRenderer.visible = false
        m.adRenderer = invalid
    end if
end sub

sub resumeVideoStream()
    destroyTruexAdRenderer()

    if m.videoPlayer <> invalid then
        m.videoPlayer.SetFocus(true)
        if m.skipSeek = invalid then
            ' resume playback from the appropriate post true[X] card point (opt-out case) or for a completed ad (opt-in + complete)
            m.videoPlayer.control = "play"
            m.videoPlayer.seek = m.videoPositionAtAdBreakPause + m.streamSeekDuration
            ? "TRUE[X] >>> ContentFlow::resumeVideoStream(position=" + StrI(m.videoPlayer.position) + ", seek=" + StrI(m.videoPositionAtAdBreakPause + m.streamSeekDuration) + ")"
        else
            ' do not touch playhead if opted out by auto-advancing past the card point
            ? "TRUE[X] >>> ContentFlow::resumeVideoStream, skipped seek (position=" + StrI(m.videoPlayer.position) + ")"
        end if
        m.skipSeek = invalid
        m.currentAdBreak = invalid
        m.streamSeekDuration = invalid
        m.videoPositionAtAdBreakPause = invalid
    end if
end sub

'-----------------------------------------------------------------------------
' Creates a ContentNode with the provided URL and starts the video player.
'
' If the IMA task has a bookmarked position the video stream will seek to it.
'
' Params:
'   url as string - the URL of the stream to play
'-----------------------------------------------------------------------------
sub beginStream(url as string)
    ? "TRUE[X] >>> ContentFlow::beginStream(url=";url;")"

    videoContent = CreateObject("roSGNode", "ContentNode")
    videoContent.url = url
    videoContent.title = m.streamData.title
    videoContent.streamFormat = "mp4"
    videoContent.playStart = 0

    m.videoPlayer.content = videoContent
    m.videoPlayer.SetFocus(true)
    m.videoPlayer.visible = true
    m.videoPlayer.retrievingBar.visible = false
    m.videoPlayer.bufferingBar.visible = false
    m.videoPlayer.retrievingBarVisibilityAuto = false
    m.videoPlayer.bufferingBarVisibilityAuto = false
    m.videoPlayer.observeFieldScoped("position", "onVideoPositionChange")
    m.videoPlayer.control = "play"
    m.videoPlayer.EnableCookies()
end sub
