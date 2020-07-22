' Copyright (c) 2019 true[X], Inc. All rights reserved.
'-----------------------------------------------------------------------------
' FetchStreamInfoTask
'-----------------------------------------------------------------------------
' Background task that requests video stream information from a provided URI.
'-----------------------------------------------------------------------------

sub init()
    ? "TRUE[X] >>> FetchStreamInfoTask::init()"
    m.top.functionName = "sendRequestForStreamConfig"
end sub

sub sendRequestForStreamConfig()
    tmp = CreateObject("roRegex", "^tmp:", "")
    pkg = CreateObject("roRegex", "^pkg:", "")

    responseCode = 0
    response = ""
    if (tmp.IsMatch(m.top.uri) OR pkg.IsMatch(m.top.uri)) then
        response = sendLocalRequest()
    else
        response = sendHTTPRequestForStreamConfig()
    end if
    
    if response <> invalid AND response.Len() > 0 then
        jsonResponse = ParseJson(response)
    
        if jsonResponse = invalid then
            m.top.error = "Unrecognized response format, expected JSON object...response=" + response
            m.top.streamInfo = invalid
        else
            m.top.streamInfo = response
        end if
    end if
end sub

'----------------------------------------------------------------------------------------------------------
' The function to be run on a background thread. Uses the provided URI (m.top.uri) to send an HTTP request
' to get the video stream information.
'
' Upon success the response JSON is parsed into an associative array and assigned to m.top.streamInfo for
' observers to respond. When errors are encountered m.top.error is updated so observers can respond.
'----------------------------------------------------------------------------------------------------------
sub sendHTTPRequestForStreamConfig()
    ? "TRUE[X] >>> FetchStreamInfoTask::sendHTTPRequestForStreamConfig()"

    m.port = CreateObject("roMessagePort")
    httpRequest = CreateObject("roUrlTransfer")
    httpRequest.SetPort(m.port)
    httpRequest.setUrl(m.top.uri)
    httpRequest.SetCertificatesFile("common:/certs/ca-bundle.crt")

    ' send the HTTP request and wait up to 5s for response
    if httpRequest.AsyncGetToString() then
        responseCode = 0
        response = ""
        event = Wait(5000, httpRequest.GetPort())
        if Type(event) = "roUrlEvent" then
            responseCode = event.GetResponseCode()
            if responseCode <> 200 then
                m.top.error = "Invalid responseCode=" + responseCode.ToStr()
                return
            end if
            response = event.GetString()
            jsonResponse = ParseJson(response)
            if jsonResponse = invalid then
                m.top.error = "Unrecognized response format, expected JSON object...response=" + response
            else
                ? "TRUE[X] >>> Stream info received, jsonResponse=";jsonResponse
                m.top.streamInfo = response
            end if
        else
            m.top.error = "Unrecognized event returned from AsyncGetToString() - URI=" + m.top.uri
        end if
    else
        m.top.error = "httpRequest.AsyncGetToString() failed"
    end if
end sub

sub sendLocalRequest() as string
    ? "TRUE[X] >>> FetchStreamInfoTask::sendLocalRequest()"
    response = ReadAsciiFile(m.top.uri).trim()
    if response.Len() > 0 then return response else return ""
end sub
