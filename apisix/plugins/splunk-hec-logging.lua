--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local core            = require("apisix.core")
local ngx             = ngx
local ngx_now         = ngx.now
local http            = require("resty.http")
local log_util        = require("apisix.utils.log-util")
local bp_manager_mod  = require("apisix.utils.batch-processor-manager")


local DEFAULT_SPLUNK_HEC_ENTRY_SOURCE = "apache-apisix-splunk-hec-logging"
local DEFAULT_SPLUNK_HEC_ENTRY_TYPE = "_json"


local plugin_name = "splunk-hec-logging"
local batch_processor_manager = bp_manager_mod.new(plugin_name)


local schema = {
    type = "object",
    properties = {
        endpoint = {
            type = "object",
            properties = {
                uri = core.schema.uri_def,
                token = {
                    type = "string",
                },
                channel = {
                    type = "string",
                },
                timeout = {
                    type = "integer",
                    minimum = 1,
                    default = 10
                }
            },
            required = { "uri", "token" }
        },
        ssl_verify = {
            type = "boolean",
            default = true
        },
    },
    required = { "endpoint" },
}


local _M = {
    version = 0.1,
    priority = 409,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function get_logger_entry(conf)
    local entry = log_util.get_full_log(ngx, conf)
    return {
        time = ngx_now(),
        host = entry.server.hostname,
        source = DEFAULT_SPLUNK_HEC_ENTRY_SOURCE,
        sourcetype = DEFAULT_SPLUNK_HEC_ENTRY_TYPE,
        event = {
            request_url = entry.request.url,
            request_method = entry.request.method,
            request_headers = entry.request.headers,
            request_query = entry.request.querystring,
            request_size = entry.request.size,
            response_headers = entry.response.headers,
            response_status = entry.response.status,
            response_size = entry.response.size,
            latency = entry.latency,
            upstream = entry.upstream,
        }
    }
end


local function send_to_splunk(conf, entries)
    local request_headers = {}
    request_headers["Content-Type"] = "application/json"
    request_headers["Authorization"] = "Splunk " .. conf.endpoint.token
    if conf.endpoint.channel then
        request_headers["X-Splunk-Request-Channel"] = conf.endpoint.channel
    end

    local http_new = http.new()
    http_new:set_timeout(conf.endpoint.timeout * 1000)
    local res, err = http_new:request_uri(conf.endpoint.uri, {
        ssl_verify = conf.ssl_verify,
        method = "POST",
        body = core.json.encode(entries),
        headers = request_headers,
    })

    if err then
        return false, "failed to write log to splunk, " .. err
    end

    if res.status ~= 200 then
        local body
        body, err = core.json.decode(res.body)
        if err then
            return false, "failed to send splunk, http status code: " .. res.status
        else
            return false, "failed to send splunk, " .. body.text
        end
    end

    return true
end


function _M.log(conf, ctx)
    local entry = get_logger_entry(conf)

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    local process = function(entries)
        return send_to_splunk(conf, entries)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, process)
end


return _M
