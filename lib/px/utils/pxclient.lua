---------------------------------------------
-- PerimeterX(www.perimeterx.com) Nginx plugin
----------------------------------------------
local M = {}

function M.load(px_config)
    local _M = {}

    local http = require "resty.http"
    local os = require "os"
    local cjson = require "cjson"
    local tostring = tostring
    local ngx_time = ngx.time
    local ngx_req_set_header = ngx.req.set_header
    local ngx_req_set_uri = ngx.req.set_uri

    local px_logger = require("px.utils.pxlogger").load(px_config)
    local px_headers = require("px.utils.pxheaders").load(px_config)
    local buffer = require "px.utils.pxbuffer"
    local px_constants = require "px.utils.pxconstants"
    local px_common_utils = require "px.utils.pxcommonutils"
    local ngx_req_get_method = ngx.req.get_method
    local pcall = pcall

    -- Server
    local auth_token = px_config.auth_token
    local ssl_enabled = px_config.ssl_enabled
    local px_server = px_config.base_url

    -- Submit is the function to create the HTTP connection to the PX collector and POST the data
    function _M.submit(data, path, pool_key)
        px_logger.debug("pxclient.submit() called")
        local px_port = px_config.px_port
        local px_debug = px_config.px_debug
        -- timeout in milliseconds
        local timeout = px_config.client_timeout
        -- create new HTTP connection
        local httpc = http.new()
        httpc:set_timeout(timeout)
        local scheme = px_config.ssl_enabled and "https" or "http"
        local ok, err = px_common_utils.call_px_server(httpc, scheme, px_server, px_port, px_config, pool_key)
        if not ok then
            px_logger.error("HTTPC connection Error: " .. err)
            error("HTTPC connection Error: " .. err)
        end
        -- Perform SSL/TLS handshake
        if ssl_enabled == true then
            local session, err = httpc:ssl_handshake()
            if not session then
                px_logger.error("HTTPC SSL handshare error: " .. err)
                error("HTTPC SSL handshare error: " .. err)
            end
        end
        -- Perform the HTTP requeset
        local res, err = httpc:request({
            path = path,
            method = "POST",
            body = data,
            headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. auth_token,
                ["Host"] = px_server
            }
        })
        if not res then
            px_logger.error("Failed to make HTTP POST: " .. err)
            error("Failed to make HTTP POST: " .. err)
        elseif res.status ~= 200 then
            px_logger.debug("Non 200 response code: " .. res.status)
            error("Non 200 response code: " .. res.status)
        else
            px_logger.debug("POST response status: " .. res.status)
        end

        -- Must read the response body to clear the buffer in order for set keepalive to work properly.
        px_logger("pxclient Must read the response body to clear the buffer in order for set keepalive to work properly.")
        local body = res:read_body()

        -- set keepalive to ensure connection pooling
        local ok, err = httpc:set_keepalive()
        if not ok then
            px_logger.error("Failed to set keepalive: " .. err)
        end
    end

    function _M.send_to_perimeterx(event_type, details)
        local buflen = buffer.getBufferLength()
        local maxbuflen = px_config.px_maxbuflen
        local full_url = ngx.var.scheme .. "://" .. ngx.var.host .. ngx.var.request_uri

        if px_config.additional_activity_handler ~= nil then
            px_logger.debug("additional_activity_handler was triggered")
            px_config.additional_activity_handler(event_type, ngx.ctx, details)
        end

        if event_type == 'page_requested' and not px_config.send_page_requested_activity then
            return
        end

        local pxdata = {}
        pxdata['type'] = event_type
        pxdata['headers'] = px_common_utils.filter_headers(px_config.sensitive_headers, false)
        pxdata['url'] = full_url
        pxdata['px_app_id'] = px_config.px_appId
        pxdata['timestamp'] = tostring(ngx_time())
        pxdata['socket_ip'] = px_headers.get_ip()

        details['http_method'] = ngx_req_get_method()
        details['module_version'] = px_constants.MODULE_VERSION
        details['risk_rtt'] = 0
        details['cookie_origin'] = ngx.ctx.px_cookie_origin
        if ngx.ctx.risk_rtt then
            details['risk_rtt'] = math.ceil(ngx.ctx.risk_rtt)
            px_logger.enrich_log('pxrtt', math.ceil(ngx.ctx.risk_rtt))
        end

        if ngx.ctx.vid then
            pxdata['vid'] = ngx.ctx.vid
            px_logger.enrich_log('pxvid', ngx.ctx.vid)
        end

        if ngx.ctx.pxhd then
            pxdata['pxhd'] = ngx.ctx.pxhd
        end

        if ngx.ctx.uuid then
            details['client_uuid'] = ngx.ctx.uuid
            px_logger.enrich_log('pxuuid',ngx.ctx.uuid)
        end

        if ngx.ctx.px_cookie then
            details['px_cookie'] = ngx.ctx.px_cookie
        end

        if ngx.ctx.px_cookie then
            details['px_cookie_hmac'] = ngx.ctx.px_cookie_hmac
        end

        if px_config.enrich_custom_parameters ~= nil then
            px_common_utils.handle_custom_parameters(px_config, px_logger, details)
        end

        if event_type == 'page_requested' then
            px_logger.debug("Sent page requested acitvity")
            details['pass_reason'] = ngx.ctx.pass_reason
            px_logger.enrich_log('pxpass', details.pass_reason)
        end

        if event_type == 'block' then
            details['simulated_block'] = not px_config.block_enabled or ngx.ctx.monitored_route == true
        end

        pxdata['details'] = details

        buffer.addEvent(pxdata)
        -- Perform the HTTP action
        if buflen >= maxbuflen then
            pcall(_M.submit, buffer.dumpEvents(), px_constants.ACTIVITIES_PATH, "px_activities")
        end
    end

    function _M.send_enforcer_telmetry(details)
        local enforcer_telemetry = {}

        details.os_name = jit.os
        details.node_name = os.getenv("HOSTNAME")
        details.module_version = px_constants.MODULE_VERSION

        enforcer_telemetry.type = 'enforcer_telemetry'
        enforcer_telemetry.px_app_id = px_config.px_appId
        enforcer_telemetry.timestamp = tostring(ngx_time())
        enforcer_telemetry.details = details

        -- Perform the HTTP action
        pcall(_M.submit, cjson.encode(enforcer_telemetry), px_constants.TELEMETRY_PATH, "px_telemetry")
        px_logger.debug("Sent enforcer telemetry")
    end

    -- Internal function that forward the requests to PerimeterX backends
    -- @server - server address to send the request to
    -- @port_overide - if provided, will overide the server default port number
    -- @allow_failure - will allow http status >= 400
    -- @pool_key - a key for the connection pool
    --
    -- @return - boolean value, success or failure
    local function forward_to_perimeterx(server, port_overide, allow_failure, pool_key)
        -- Attach real ip from the enforcer
        ngx_req_set_header(px_constants.ENFORCER_TRUE_IP_HEADER, px_headers.get_ip())
        ngx_req_set_header(px_constants.FIRST_PARTY_HEADER, '1')

        -- change the host so BE knows where to serve the request
        ngx_req_set_header('host', server)

        local port = ngx.var.scheme == 'http' and 80 or 443
        if port_overide ~= nil then
            px_logger.debug('Overrding port ' .. port ..  ' => ' .. port_overide)
            port =  port_overide
        end
        px_logger.debug("Using " .. ngx.var.scheme .. " port " .. port)
        local httpc = http.new()

        httpc:set_timeout(2000)

        local scheme = ngx.var.scheme == 'http' and 'http' or 'https'
        local call_pool_key = pool_key .. '-' .. scheme

        local ok, err = px_common_utils.call_px_server(httpc, scheme, server, port, px_config, call_pool_key)

        if not ok then
            ngx.log(ngx.ERR, err)
            return false
        end

        if port == 443 and ssl_enabled then
            local session, err = httpc:ssl_handshake()
            if not session then
                px_logger.error("HTTPC SSL handshare error: " .. err)
                return
            end
        end

        local res, err = httpc:proxy_request()

        -- return false only if we dont allow failer and we got error or
        -- status >= 400
        if not allow_failure and (err or res.status >= 400) then
            return false
        end

        httpc:proxy_response(res)
        httpc:set_keepalive()

        ngx.exit(ngx.status)
        return true
    end

    -- inteneral function, handles first party response that failed/bad status
    -- return true for handled request
    local function default_response(content_type, content)
        px_logger.debug('Rendering default reponse on route ' .. ngx.var.uri .. ', content type: ' .. content_type .. ', body ' .. content)
        ngx.header["Content-Type"] = content_type
        ngx.print(content)
        ngx.exit(ngx.OK)
        return true
    end

    function _M.reverse_px_client(reverse_prefix, lower_request_url)
        if not string.find(lower_request_url, string.lower("/" .. reverse_prefix .. px_constants.FIRST_PARTY_VENDOR_PATH)) then
            return false
        end

        -- Prepare default response
        local default_content_type = 'application/javascript'
        local default_content = ''

        if not px_config.first_party_enabled then
            return default_response(default_content_type, default_content)
        end

        local path = "/" .. px_config.px_appId .. "/main.min.js"
        local px_request_uri
        if (ngx.var.scheme == 'http' and px_config.proxy_url) then
            px_request_uri = 'http://' .. px_config.client_host  .. path
        else
            px_request_uri = path
        end

        px_logger.debug("Forwarding request from "  .. ngx.var.uri .. " to client at " .. px_config.client_host  .. path)
        ngx_req_set_uri(px_request_uri)
        px_common_utils.clear_first_party_sensitive_headers(px_config.sensitive_headers)

        forward_to_perimeterx(px_config.client_host, px_config.client_port_overide, true, "px_client")

        return true
    end

    function _M.reverse_px_captcha(reverse_prefix, lower_request_url)
        if not string.find(lower_request_url, string.lower("/" .. reverse_prefix .. px_constants.FIRST_PARTY_CAPTCHA_PATH)) then
            return false
        end

        -- Prepare default response
        local default_content_type = 'application/javascript'
        local default_content = ''

        if not px_config.first_party_enabled then
            return default_response(default_content_type, default_content)
        end

        local path = string.gsub(ngx.var.uri, '/' .. reverse_prefix .. px_constants.FIRST_PARTY_CAPTCHA_PATH, '')
        local px_request_uri
        if (ngx.var.scheme == 'http' and px_config.proxy_url) then
            px_request_uri = 'http://' .. px_config.captcha_script_host  .. path
        else
            px_request_uri = path
        end


        px_logger.debug("Forwarding request from "  .. ngx.var.request_uri .. " to px captcha at " .. px_config.captcha_script_host .. path)
        ngx_req_set_uri(px_request_uri)

        px_common_utils.clear_first_party_sensitive_headers(px_config.sensitive_headers)
        forward_to_perimeterx(px_config.captcha_script_host, nil, true, "px_captcha")

        return true
    end

    function _M.reverse_px_xhr(reverse_prefix, lower_request_url)
        if not string.find(lower_request_url, string.lower("/" .. reverse_prefix .. px_constants.FIRST_PARTY_XHR_PATH)) then
            return false
        end

        -- prepare defualt response
        local default_content_type =  'application/json'
        local default_content = '{}'

        if string.match(ngx.var.uri, 'gif') then
            default_content_type = 'image/gif'
            default_content = ngx.decode_base64(px_constants.EMPTY_GIF_B64)
        end

        if not px_config.first_party_enabled or not px_config.reverse_xhr_enabled then
            return default_response(default_content_type, default_content)
        end

        local path = string.gsub(ngx.var.uri, '/' .. reverse_prefix .. px_constants.FIRST_PARTY_XHR_PATH, '')
        local px_request_uri
        if (ngx.var.scheme == 'http' and px_config.proxy_url) then
            px_request_uri = 'http://' .. px_config.collector_host  .. path
        else
            px_request_uri = path
        end

        px_logger.debug("Forwarding request from "  .. ngx.var.request_uri .. " to xhr at " .. px_config.collector_host .. path)
        ngx_req_set_uri(px_request_uri)

        local vid = ''

        if ngx.var.cookie__pxvid then
            vid = ngx.var.cookie__pxvid
        elseif ngx.var.cookie_pxvid then
            vid = ngx.var.cookie_pxvid
        end

        px_common_utils.clear_first_party_sensitive_headers(px_config.sensitive_headers)

        if vid ~= '' then
            px_logger.debug("Attaching VID cookie" .. vid)
            ngx_req_set_header('cookie', 'pxvid=' .. vid)
        end

        local xff_header = ngx.req.get_headers()['X-Forwarded-For']
        if xff_header then
            xff_header = xff_header .. ', ' .. ngx.var.remote_addr
        else
            xff_header = ngx.var.remote_addr
        end
        ngx_req_set_header('X-Forwarded-For', xff_header)
        local status = forward_to_perimeterx(px_config.collector_host, px_config.collector_port_overide, false, "px_xhr")

        if not status  then
            return default_response(default_content_type, default_content)
        end

        return true
    end

    return _M
end

return M
