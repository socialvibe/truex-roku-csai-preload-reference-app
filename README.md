# Overview

This project contains sample source code that demonstrates how to integrate true[X]'s Roku
ad renderer. This further exemplifies the needed logic to manage true[X] opt-in flows (choice cards) as 
fully stitched into the video stream. 

For a more detailed integration guide, please refer to: https://github.com/socialvibe/truex-roku-integrations.

# Implementation Details

In this project we simulate the integration with a live Ad Server (CSAI use case) or SSAI provider through a mock ad playlist configuration. This is meant to capture the stream's ad pods, including their duration and the reference to the true[X] payloads in each pod. This configuration is maintained in `res/reference-app-streams.json` as part of the `vmap` key. In this sample channel, two ad breaks are defined, `preroll` and `midroll-1`. The duration of the true[X] specific Choice Card video asset is called out as well as the duration of the standard video ads. This is a simplified representation of what would otherwise come through a provider-dependent XML or JSON syntax, but should be sufficient to exemplify the flow. The stream location itself is maintained in the `url` value.

This `vmap` ad playlist is marshaled through to the `ContentFlow` SceneGraph Component which handles the stream playback. In `preprocessVmapData` we parse out this ad playlist and build simple data structures which are then referenced as part of the video position change handler (`onVideoPositionChange`) to detect when we encounter a true[X] ad pod. We then initialize and launch the true[X] ad with the `isOneStageIntegration` flag, which indicates to the TruexAdRenderer that it should defer to the host channel's video player and stream for choice card asset rendering. Note that because we defer we also need the channel to notify the TruexAdRenderer when playback has moved on past the choice card, which we do so also from `onVideoPositionChange` using the `stop` action.

The `onTruexEvent` subroutine handles true[X] events and repositions the playhead depending on whether the viewer completed an ad or not (earning an ad pod skip in the former case). 
