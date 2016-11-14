---------------------------------------------
-- PerimeterX(www.perimeterx.com) Nginx plugin
-- Version 1.1.4
-- Release date: 07.11.2016
----------------------------------------------

local ngx_HTTP_FORBIDDEN = ngx.HTTP_FORBIDDEN
local ngx_say = ngx.say
local px_client = require "px.utils.pxclient"
local px_config = require "px.pxconfig"
local px_constants = require "px.utils.pxconstants"
local ngx_exit = ngx.exit
local _M = {}

function _M.block(reason)
    local details = {}
    local ref_str = ''
    local vid = ''
    local uuid = ''
    local score = 0

    details.module_version = px_constants.MODULE_VERSION
    if reason then
        details.block_reason = reason
    end

    if ngx.ctx.uuid then
        uuid = ngx.ctx.uuid
        details.block_uuid = uuid
        ref_str = '<span style="font-size: 20px;">Block Reference: <span style="color: #525151;">#' .. uuid .. '</span></span>';
    end

    if ngx.ctx.block_score then
        score = ngx.ctx.block_score
        details.block_score = score
    end

    if ngx.ctx.vid then
        vid = ngx.ctx.vid
    end

    px_client.send_to_perimeterx('block', details);
    if px_config.block_enabled then
        ngx.status = ngx_HTTP_FORBIDDEN;
        ngx.header["Content-Type"] = 'text/html';
        if px_config.captcha_enabled then
            local head = '<head> <link href="http://fonts.googleapis.com/css?family=Open+Sans:300italic,400italic,600italic,700italic,800italic,400,300,600,700,800" media="screen, print" rel="stylesheet" type="text/css"> <link href="https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css" rel="stylesheet" integrity="sha384-wvfXpqpZZVQGK6TAh5PVlGOfQNHSoD2xbE+QkPxCAFlNEevoEH3Sl0sibVcOQVnN" crossorigin="anonymous"> <meta charset="utf-8"> <title> Access to This Page Has Been Blocked </title> <style> h2 { color: white; font-size: 32px; } p { width: 60%; margin: 0 auto; font-size: 35px; } body { background-color: black; font-family: "Open Sans"; margin: 5%; color: white; text-align: center; } img { widht: 180px; } a { color: #2020B1; text-decoration: blink; } a:hover { color: white; } i { color:#E5001D; } </style> <script src="https://www.google.com/recaptcha/api.js"> </script> <script> window.px_vid = "' .. vid .. '"; function handleCaptcha(response) { var name = "_pxCaptcha"; var expiryUtc = new Date( Date.now() + 1000 * 10 ).toUTCString(); var cookieParts = [name, "=", response + ":" + window.px_vid, "; expires=", expiryUtc, "; path=/"]; document.cookie = cookieParts.join(""); location.reload(); } </script></head>'
            local body = '<body cz-shortcut-listen="true"><div> <img src="http://storage.googleapis.com/instapage-thumbnails/035ca0ab/e94de863/1460594818-1523851-467x110-perimeterx.png"> </img></div><h2> Custom Main Title</h2><div style="font-size: 24px;"> <br> <div style="color:#E5001D"> <i class="fa fa-user-secret fa-6" aria-hidden="true" style="font-size: 130px"></i><br> For some reason, we think you are a bot ! </div> <br> <div style="margin-bottom: 20px; color: gold"> This may have happend because: </div> <div> <i class="fa fa-dot-circle-o" aria-hidden="true"></i> JavaScript is disabled or not running properly. </div> <div> <i class="fa fa-dot-circle-o" aria-hidden="true"></i> Your browsing behaviour is not likely to be that of a regular user. </div> <br> To read more about the bot defender solution: <a href="https://www.perimeterx.com/bot-defender"> https://www.perimeterx.com/bot-defender </a> <br> If you think the blocking was done by mistake, contact the site administrator. <br> <br> <div> <div class="g-recaptcha" data-callback="handleCaptcha" data-sitekey="6Lcj-R8TAAAAABs3FrRPuQhLMbp5QrHsHufzLf7b" data-theme="dark" style="margin:0 auto; width:304px"> </div> <span style="font-size: 14px; color:#E5001D ">Solve the reCAPTCHA above to prove you are not a bot!</span> </div> <br> ' .. ref_str .. '</div></body>';
            ngx_say('<html lang="en">' .. head .. body .. '</html>');
        else
            ngx_say('<html lang="en"><head> <link type="text/css" rel="stylesheet" media="screen, print" href="//fonts.googleapis.com/css?family=Open+Sans:300italic,400italic,600italic,700italic,800italic,400,300,600,700,800"> <meta charset="UTF-8"> <title>Access to This Page Has Been Blocked</title> <style> p { width: 60%; margin: 0 auto; font-size: 35px; } body { background-color: #a2a2a2; font-family: "Open Sans"; margin: 5%; } img { widht: 180px; } a { color: #2020B1; text-decoration: blink; } a:hover { color: #2b60c6; } </style> <style type="text/css"></style></head><body cz-shortcut-listen="true"><div><img src="http://storage.googleapis.com/instapage-thumbnails/035ca0ab/e94de863/1460594818-1523851-467x110-perimeterx.png"></div><span style="color: white; font-size: 34px;">Access to This Page Has Been Blocked</span><div style="font-size: 24px;color: #000042;"><br> Access to this page is blocked according to the website security policy. <br> Your browsing activities made us think you may be a bot. <br> <br> This may happen as a result of the following: <ul> <li>JavaScript is disabled or not running properly.</li> <li>Your browsing behaviour is  not likely to be a regular user.</li> </ul> To read more about the bot defender solution: <a href="https://www.perimeterx.com/bot-defender">https://www.perimeterx.com/bot-defender</a> <br> If you think the blocking was done by mistake, contact the site administrator. <br> <br> </br>' .. ref_str .. '</div></body></html>')
        end
        ngx_exit(ngx.OK);
    else
        return true
    end
end

return _M
