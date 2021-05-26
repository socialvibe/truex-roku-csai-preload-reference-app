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

    ' store reference to video player
    m.videoPlayer = m.top.findNode("videoPlayer")
    ' tracks whether an `adFreePod` was received from true[X] which should skip the rest of the ads in a pod
    m.skipAds = false
    ' tracks whether a pod of standard video ads is currently playing, so that true[X] ads do not get triggered
    m.playingVideoAds = false

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
' Full documentation for the below events can be found here: https://github.com/socialvibe/truex-roku-integrations/blob/develop/DOCS.md
'
' The following event types are supported:
'   * adFreePod - user has met engagement requirements, skips past remaining pod ads
'   * adStarted - user has started their ad engagement
'   * adFetchCompleted - TruexAdRenderer received ad fetch response
'   * optOut - user has opted out of true[X] engagement, show standard ads
'   * optIn - this event is triggered when a user decides opt-in to the true[X] interactive ad
'   * adCompleted - user has finished the true[X] engagement, resume the video stream
'   * adError - TruexAdRenderer encountered an error presenting the ad, resume with standard ads
'   * adsAvailable - TruexAdRenderer has an ad ready to present 
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
        ' user has earned credit for the engagement, ensure video ads are skipped when stream is resumed
        m.skipAds = true
    else if data.type = "adStarted" then
        ' this event is triggered when the true[X] Choice Card is presented to the user
    else if data.type = "adFetchCompleted" then
        ' this event is triggered when TruexAdRenderer receives a response to an ad fetch request
    else if data.type = "optOut" then
        ' this event is triggered when a user decides not to view a true[X] interactive ad
        ' that means the user was presented with a Choice Card and opted to watch standard video ads
        ' we should resume the stream from the video ads
    else if data.type = "optIn" then
        ' this event is triggered when a user decides opt-in to the true[X] interactive ad
    else if data.type = "adCompleted" then
        ' this event is triggered when TruexAdRenderer is done presenting the ad
        ' if the user earned credit (via "adFreePod") their content will be seeked past the ad break
        ' if the user has not earned credit they will resume at the beginning of the ad break
        resumeVideoStream()
    else if data.type = "adError" then
        ' this event is triggered whenever TruexAdRenderer encounters an error
        ' usually this means the video stream should continue with normal video ads
        resumeVideoStream()
    else if data.type = "adsAvailable" then
        ' this event is triggered when TruexAdRenderer receives an usable true[X] ad in the ad fetch response
    else if data.type = "noAdsAvailable" then
        ' this event is triggered when TruexAdRenderer receives no usable true[X] ad in the ad fetch response
        ' usually this means the video stream should continue with normal video ads
        resumeVideoStream()
    else if data.type = "userCancel" then
        ' This event will fire when a user backs out of the true[X] interactive ad unit after having opted in. 
        ' The flow goes back to the Choice Card opt-in flow within the true[X] experience.
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

sub preloadTruexAd()
    ? "TRUE[X] >>> ContentFlow::preloadTruexAd()"

    decodedData = m.currentAdBreak
    if decodedData = invalid then return

    ? "TRUE[X] >>> ContentFlow::preloadTruexAd() - ad break: " ; decodedData

    ' Populating the test ad from the pod parsed out from `preprocessVmapData()`
    adPayload = decodedData.truexParameters

    ? "TRUE[X] >>> ContentFlow::preloadTruexAd() - instantiating TruexAdRenderer ComponentLibrary..."

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
        channelWidth: 1280, ' Optional parameter, set the width in pixels of the channel's interface, defaults to 1920
        channelHeight: 720 ' Optional parameter, set the height in pixels of the channel's interface, defaults to 1080
    }

    ? "TRUE[X] >>> ContentFlow::preloadTruexAd() - initializing TruexAdRenderer with action=";tarInitAction
    m.adRenderer.action = tarInitAction
end sub

'--------------------------------------------------------------------------------------------------------
' Launches the true[X] renderer based on the current ad break as detected by onVideoPositionChange
'--------------------------------------------------------------------------------------------------------
sub launchTruexAd()
    ? "TRUE[X] >>> ContentFlow::launchTruexAd()"

    ' Preload on the fly if true[X] not "warm" already.
    if m.adRenderer = invalid then preloadTruexAd()

    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - starting ad at video position: ";m.videoPlayer.position

    ' Hedge against Roku playhead imprecision by adding buffer so that non choice card content is not shown
    m.videoPositionAtAdBreakPause = m.videoPlayer.position + 0.5

    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - starting TruexAdRenderer..."
    m.adRenderer.action = { type: "start" }
    m.adRenderer.focusable = true
    m.adRenderer.SetFocus(true)
end sub

'--------------------------------------------------------------------------------------------------------
' Launches video ads used when a viewer opted out of true[X], ads were not available or in case of error.
'--------------------------------------------------------------------------------------------------------
sub launchVideoAds()
    ? "TRUE[X] >>> ContentFlow::launchVideoAds()"

    decodedData = m.currentAdBreak
    if decodedData = invalid then return

    ' Use the video ad playlist parsed out for this pod in `preprocessVmapData()`
    m.videoPlayer.content = decodedData.videoAdPlaylist
    m.videoPlayer.contentIsPlaylist = true
    m.videoPlayer.position = 0
    m.videoPlayer.control = "play"
    m.playingVideoAds = true
end sub

'--------------------------------------------------------------------------------------------------------
' Callback triggered when the video player's playhead changes. Used to keep track of ad pods and 
' trigger the instantiation of the true[X] experience.
''--------------------------------------------------------------------------------------------------------
sub onVideoPositionChange()
    ? "TRUE[X] >>> ContentFlow::onVideoPositionChange: " + Str(m.videoPlayer.position) + " duration: " + Str(m.videoPlayer.duration)
    if m.vmap = invalid or m.vmap.Count() = 0 or m.playingVideoAds then return

    ' Check to see if playback has entered a true[X] spot, and if so, start true[X].
    for each vmapEntry in m.vmap
        if vmapEntry.startOffset <> invalid and vmapEntry.played <> invalid and vmapEntry.preloaded <> invalid then
            ' see if we have an incoming pod with a true[X] within the next 2 minutes, and if so, preload it
            if m.videoPlayer.position + 120 >= vmapEntry.startOffset and not vmapEntry.preloaded then
                ' we have entered an non preloaded ad pod, trigger preloading of true[X] ad
                ? "TRUE[X] >>> ContentFlow::onVideoPositionChange: hit a pod for preloading: " ; vmapEntry
                vmapEntry.preloaded = true
                m.currentAdBreak = vmapEntry

                ' Preload true[X] ads if they were defined (returned from the ad server or CMS in a real world scenario).
                if vmapEntry.truexParameters <> invalid and m.adRenderer = invalid then
                    ? "TRUE[X] >>> ContentFlow::onVideoPositionChange: preloading true[X] tag with parameters: " ; vmapEntry.truexParameters
                    preloadTruexAd()
                end if
            end if 

            if m.videoPlayer.position >= vmapEntry.startOffset and not vmapEntry.played then
                ' we have entered an unplayed ad pod, stop main stream and trigger ads
                ? "TRUE[X] >>> ContentFlow::onVideoPositionChange: hit a pod for starting: " ; vmapEntry
                vmapEntry.played = true
                m.videoPlayer.control = "stop"

                ' Start true[X] ads, alternatively fall back to video ads.
                if vmapEntry.truexParameters <> invalid then
                    ? "TRUE[X] >>> ContentFlow::onVideoPositionChange: launching true[X] tag with parameters: " ; vmapEntry.truexParameters
                    launchTruexAd()
                else if vmapEntry.videoAdPlaylist <> invalid then
                    launchVideoAds()
                end if                
            end if
        end if 
    end for
end sub

'--------------------------------------------------------------------------------------------------------
' Callback triggered when the video player's state changes. Used to transition from the video ad pod back
' to the content stream when the former completes playback.
''--------------------------------------------------------------------------------------------------------
sub onVideoStateChange()
    ? "TRUE[X] >>> ContentFlow::onVideoStateChange: " ; m.videoPlayer.state ; " contentIndex: " ; m.videoPlayer.contentIndex

     if m.videoPlayer.state = "finished" then
        if m.playingVideoAds then
            m.playingVideoAds = false
            resumeContentStream()
        else
            ' Content stream completed playback, return to the parent scene.
            tearDown()
            m.top.event = { trigger: "cancelStream" }
        end if
    else if m.videoPlayer.state = "error" then
        ? "TRUE[X] >>> ContentFlow::onVideoStateChange: ERROR: " ; m.videoPlayer.errorStr
        tearDown()
        m.top.event = { trigger: "cancelStream" }
    end if
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

    ' extract out ad pods and their contents - simulates the kind of data a CMS or ad server would provide
    ' in a real world context.
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
' runtime. These pods are defined in the res/reference-app-streams.json file and 
' emulate what would come down from a CMS or ad server as the playlist
' of ads for the current stream.
' 
' The extracted pods will be "client side inserted" as the playhead crosses 
' past the `timeOffset` defined in said pod.
'----------------------------------------------------------------------------------
sub preprocessVmapData(vmapJson as object)
    if vmapJson = invalid or Type(vmapJson) <> "roArray" return
    m.vmap = []
    ? "TRUE[X] >>> ContentFlow::preprocessVmapData, vmapJson" ; vmapJson

    for i = 0 to vmapJson.Count() - 1
        vmapEntry = vmapJson[i]
        newPod = {}
        timeOffset = vmapEntry.timeOffset
        breakId = vmapEntry.breakId
        podAds = vmapEntry.ads

        if timeOffset <> invalid and breakId <> invalid and podAds <> invalid then
            newPod.timeOffset = timeOffset
            newPod.breakId = breakId
            newPod.played = false
            newPod.preloaded = false
            
            ' parse out the ad insertion point and turn into seconds
            timeOffset = timeOffset.Left(8)
            timeOffsetComponents = timeOffset.Split(":")
            timeOffsetSecs = timeOffsetComponents[2].ToInt() + timeOffsetComponents[1].ToInt() * 60 + timeOffsetComponents[0].ToInt() * 3600
            ? "TRUE[X] >>> ContentFlow::preprocessVmapData, #" ; i + 1 ; ", timeOffset: "; timeOffset ; ", start: " ; timeOffsetSecs
            newPod.startOffset = timeOffsetSecs
            newPod.podindex = i
            ' define the video ad playlist for this pod
            newPod.videoAdPlaylist = createObject("RoSGNode", "ContentNode")      

            ' Populate the ads in this pod.
            ' For simplicity, the true[X] ad is stored here as its `adParameters` structure which would normally get returned 
            ' via the channel's ad server hitting true[X]'s own ad server VAST endpoint.
            ' The video ads are instantiated directly as a `ContentNode` playlist ready to be fed to Roku's video player.
            for j = 0 to podAds.Count() - 1
                adEntry = podAds[j]
                
                if adEntry.adType = "truex" then
                    newPod.truexParameters = adEntry.adParameters
                else if adEntry.adType = "video" then
                    ? "TRUE[X] >>> ContentFlow::preprocessVmapData, adding video ad #" ; j + 1 ; ", url: "; adEntry.adParameters.url ; ", title: " ; adEntry.adParameters.title
                    adContentNode = CreateObject("roSGNode", "ContentNode")
                    adContentNode.url = adEntry.adParameters.url
                    adContentNode.title = adEntry.adParameters.title
                    adContentNode.streamFormat = "mp4"
                    adContentNode.playStart = 0
                    newPod.videoAdPlaylist.appendChild(adContentNode)
                end if                
            end for

            ? "TRUE[X] >>> ContentFlow::preprocessVmapData, adding pod: " ; newPod
            m.vmap.Push(newPod)
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

'-----------------------------------------------------------------------------------
' Clean up after the viewer stops or ends this stream.
'-----------------------------------------------------------------------------------
sub tearDown()
    destroyTruexAdRenderer()
    if m.videoPlayer <> invalid then m.videoPlayer.control = "stop"
end sub

'-----------------------------------------------------------------------------------
' Clean up true[X] renderer.
'-----------------------------------------------------------------------------------
sub destroyTruexAdRenderer()
    if m.adRenderer <> invalid then
        m.adRenderer.SetFocus(false)
        m.top.removeChild(m.adRenderer)
        m.adRenderer.visible = false
        m.adRenderer = invalid
    end if
end sub

'-----------------------------------------------------------------------------------
' Resume playback of the viewing session, called after true[X] flow ends.
'
' Either pick up from the content stream, assuming we are skipping over ads, 
' alternatively launch the video ads.
'-----------------------------------------------------------------------------------
sub resumeVideoStream()
    destroyTruexAdRenderer()

    if m.videoPlayer <> invalid then
        m.videoPlayer.SetFocus(true)
        if m.skipAds then
            ' skipping ads in this CSAI example simply involves resuming the original, ad free content stream
            resumeContentStream()
        else
            ' else launch the current batch of video ads from the currently active pod
            ? "TRUE[X] >>> ContentFlow::resumeVideoStream, playing video ads (position=" + StrI(m.videoPlayer.position) + ")"
            launchVideoAds()
        end if
        m.skipAds = false
        m.currentAdBreak = invalid
    end if
end sub

'-----------------------------------------------------------------------------------
' Resume playback of the content stream, will seek to the point playback was interrupted 
' from when true[X] flow was kicked off.
'-----------------------------------------------------------------------------------
sub resumeContentStream()
    videoContent = CreateObject("roSGNode", "ContentNode")
    videoContent.url = m.streamData.url
    videoContent.title = m.streamData.title
    videoContent.streamFormat = "mp4"
    videoContent.playStart = 0
    m.videoPlayer.content = videoContent

    m.videoPlayer.contentIsPlaylist = false
    m.videoPlayer.control = "play"
    positionToResumeAt = 0
    if m.videoPositionAtAdBreakPause <> invalid then positionToResumeAt = m.videoPositionAtAdBreakPause
    m.videoPlayer.seek = positionToResumeAt
    ? "TRUE[X] >>> ContentFlow::resumeContentStream(position=" + StrI(m.videoPlayer.position) + ", seek=" + StrI(positionToResumeAt) + ")"
end sub

'-----------------------------------------------------------------------------
' Creates a ContentNode with the provided URL and starts the video player.
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
    m.videoPlayer.observeFieldScoped("state", "onVideoStateChange")
    m.videoPlayer.control = "play"
    m.videoPlayer.EnableCookies()
end sub
