# Overview

This project contains sample source code that demonstrates how to integrate true[X]'s Roku ad renderer end-to-end. This further exemplifies how true[X] may be integrated within a channel that has client side ad insertion for its video ads. 

The `res/reference-app-streams.json` file simulates what the host's CMS or Ad Server would return for the stream, including ad information. The app then creates true[X] and skips the rest of the video ads if the user successfully completes the experience.

For a more detailed integration guide, please refer to: https://github.com/socialvibe/truex-roku-integrations.

# Implementation Details

In this project we simulate the integration with a live true[X] Ad Server via through a mock stream playlist configuration. This is meant to capture the stream's ad pods, including their duration and the reference to the true[X] and video ad payloads in each pod. This configuration is maintained in `res/reference-app-streams.json` as part of the `vmap` key. In this sample channel, two ad breaks are defined, `preroll` and `midroll`. This is a simplified representation of what would otherwise come through a provider-dependent XML or JSON syntax, but should be sufficient to exemplify the flow. The demo `mp4` stream location itself is maintained in the `url` value.

This `vmap` ad playlist is marshaled through to the `ContentFlow` SceneGraph Component which handles the stream playback. In `preprocessVmapData` we parse out this ad playlist and build simple data structures which are then referenced as part of the video position change handler (`onVideoPositionChange`) to detect when we encounter a true[X] ad pod. We then initialize and launch the true[X] ad when crossing over one of the defined pods. 

The `onTruexEvent` subroutine handles true[X] events notably keeping track of whether the viewer successfully met the completion criteria for true[X] (`adFreePod` event). 

In `resumeVideoStream` we resume playback of the ad free content stream, or the current pod of video ads, depending on whether that completion criteria was met.

## Preloading

This channel also demonstrates how to preload true[X] ads. This is simply accomplished by initializing, but not yet starting a truexAdRenderer instance. 

This logic can be found in `onVideoPositionChange`. We create and add the renderer to the scene ahead of time (by 2 mins in this example), however only start it when we get to the appropriate ad insertion point.
