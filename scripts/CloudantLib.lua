--
--   Copyright 2014 John Pormann, Duke University
--
--   Licensed under the Apache License, Version 2.0 (the "License");
--   you may not use this file except in compliance with the License.
--   You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
--   Unless required by applicable law or agreed to in writing, software
--   distributed under the License is distributed on an "AS IS" BASIS,
--   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--   See the License for the specific language governing permissions and
--   limitations under the License.
--

local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require( "json" )
local socketurl = require( "socket.url" ) -- for urlencode/escape

local Cloudant = {}

function Cloudant.new( params )

	-- defaults	
	local grp = {
		baseurl = "https://default.cloudant.com",
		database = "default",
		username = "default",
		password = "default",
		sessionauth = "default",
		synchronous = false,
		query = "default",
		uuid = 0,
		rev  = 0,
		data = 0,
		file = "default",
		headers = {},
		onComplete = function(e)
			print( "default CloudantObj.onComplete function called" ) 
		end
	}
	
	if( params ~= nil ) then
		for k,v in pairs(params) do
			if( grp[k] == nil ) then
				-- there is no such key in the default object
				-- so let's skip it
			else
				grp[k] = v
			end
		end
	end
	
	--
	-- the "internal" worker-functions
	function grp.handleUploadResponse( event )
		-- need to fudge a last_response table
		-- so that uuid="LAST" still works
		grp.last_response = {}
		grp.last_response.entities = {}
		grp.last_response.entities[1] = {}
		grp.last_response.entities[1].uuid = grp.old_uuid
	end
	
	function grp.handleDownloadResponse( event )
		-- need to fudge a last_response table
		-- so that uuid="LAST" still works
		grp.last_response = {}
		grp.last_response.entities = {}
		grp.last_response.entities[1] = {}
		grp.last_response.entities[1].uuid = grp.old_uuid
		
		-- store the file
		local path = system.pathForFile( grp.old_data.filename, grp.old_data.baseDirectory )
		print( "path ["..path.."]" )
		local fp = io.open( path, "w" )
		if( event.response ~= nil ) then
			print( "response ["..event.response.."]" )
			fp:write( event.response )
		end
		fp:close()
		
		event.downloadInfo = {
			filename = grp.old_data.filename,
			baseDirectory = grp.old_data.baseDirectory,
			path = path,
		}
	end

	function grp.baseNetworkListener( event )
		print( "network_num_tries = "..grp.network_num_tries )
		
		-- regardless of whether there is an error or not,
		-- we need to clear out the old uuid/data areas
		grp.old_uuid = grp.uuid
		grp.old_data = grp.data
		grp.uuid = 0
		grp.data = 0
		
		local ee = {
			name = "CloudantResponse",
			target = grp,
			isError = event.isError,
			status = event.status,
			response = event.response,
			responseHeaders = event.responseHeaders,
		}
		
		if( event.isError ) then
			print( "Network error!")
			if( grp.network_num_tries > 0 ) then
				print( "  trying again" )
				grp.network_num_tries = grp.network_num_tries + 1
			else
				print( " too many retries" )
				if( grp.onComplete ~= nil ) then
					ee.isError = true
					grp.onComplete( ee )
				else
					print( "onComplete is nil (error)" )
				end
			end
		else
			print( "response is ok" )
			if( grp.command == "up_file" ) then
				print( "found an upload response" )
				grp.handleUploadResponse( event )
			elseif( grp.command == "dn_file" ) then
				print( "found a download response" )
				grp.handleDownloadResponse( event )
			else
				--print( "response ["..event.response.."]" )
				local resp = json.decode( event.response )
				local respHdrs = event.responseHeaders
				--print( "resp = "..tostring(resp) )
				grp.last_response = resp
				grp.last_response_headers = respHdrs
				print_r( respHeaders )
				if( respHdrs["set-cookie"] ~= nil ) then
					print( "found a response cookie" )
					grp.sessionauth = respHdrs["set-cookie"]
					print( "got authtoken ["..grp.sessionauth.."]" )
				end
			end
			if( grp.onComplete ~= nil ) then
				--print( "calling func "..tostring(grp.onComplete) )
				grp.onComplete( ee )
			else
				print( "onComplete is nil" )
			end
		end
	end
	
	function grp.synchrNetworkRequest( url, httpverb, auxdata )
		local rtn = {
			name = "CloudantResponse",
			target = grp,
			isError = false,
			status = 100,
			response = "IN_PROGRESS",
			responseHeaders = {},
		}
		
		if( auxdata.body ~= nil ) then
			auxdata.headers["Content-Length"] = string.len(auxdata.body)
		end
		
		local response_body = {}
		local idx,statusCode,resp_hdrs = http.request({
			method = httpverb,
			url = url,
			headers = auxdata.headers,
			source = ltn12.source.string(auxdata.body),
			sink = ltn12.sink.table(response_body),
		})

		if( idx ~= 1 ) then
			print( "** ERROR: http.request returned idx="..idx.." (expected 1)" )
		end

		-- we may have more than 1 chunk of data .. stitch it all together
		local n = #response_body
		print( "found "..n.." chunks of data" )
		local resp_txt = ""
		for i=1,n do
			print( "  chunk "..i.." = "..#response_body[i] .. " bytes" )
			resp_txt = resp_txt .. response_body[i]
		end
		
		rtn.isError = false
		rtn.status = statusCode
		if( resp_txt ~= nil ) then
			rtn.response = json.decode( resp_txt )
		end
		--rtn.response = resp_txt
		rtn.responseHeaders = resp_hdrs
		grp.last_response = rtn.response
		grp.last_response_headers = rtn.responseHeaders

		if( resp_hdrs["set-cookie"] ~= nil ) then
			print( "found a response cookie" )
			grp.sessionauth = resp_hdrs["set-cookie"]
			print( "got authtoken ["..grp.sessionauth.."]" )
		end
		
		return rtn
	end

	function grp.CloudantWorker( httpverb, url, auxdata )
		local rtn = {
			name = "CloudantResponse",
			target = grp,
			isError = false,
			status = 100,
			response = "{\"status\": \"IN_PROGRESS\"}",
			responseHeaders = {},
		}
		grp.inProgress = true
		grp.network_num_tries = 1

		print( "final http request ("..httpverb..") ["..url.."]" )
		if( grp.sessionauth ~= nil ) then
			if( grp.sessionauth ~= "default" ) then
				print( "  valid sessionauth token found" )
			end
		end
		if( auxdata.headers ~= nil ) then
			print( "  extra headers found" )
			for k,v in pairs(auxdata.headers) do
				print( "    ["..k.."]=["..v.."]" )
			end
		end
		if( auxdata.body ~= nil ) then
			print( "  body data found ["..auxdata.body.."]" )
		end
		
		if( grp.synchronouse == false ) then
			network.request( url, httpverb, grp.baseNetworkListener, auxdata )
		else
			rtn = grp.synchrNetworkRequest( url, httpverb, auxdata )
		end
		return rtn
	end

	-- TODO: may need to put this behind timer.performWithDelay
	-- or else main thread will throw error/onComplete func before
	-- the program ever had a chance to respond 
	function grp.throwError( resp )
		local rtn = {
			name = "CloudantResponse",
			target = grp,
			isError = true,
			status = 400,
			response = "ERROR",
		}
		if( grp.synchronous == false ) then
			if( grp.onComplete ~= nil ) then
				grp.onComplete( ee )
			end
		end
		return rtn
	end
	
	function grp.handleXtra( xtra )
		if( xtra ~= nil ) then
			-- now overwrite with xtra data
			for k,v in pairs(xtra) do
				if( grp[k] ~= nil ) then
					grp[k] = v
				end
			end
			-- TODO: "info" action doesn't return id, so "LAST" doesn't work
			if( grp.uuid == "LAST" ) then
				if( grp.last_response ~= nil ) then
					if( grp.last_response.id ~= nil ) then
						-- "create" action returns "id"
						grp.uuid = grp.last_response.id
					elseif( grp.last_response._id ~= nil ) then
						-- other actions return "_id"
						grp.uuid = grp.last_response._id
					end
				end
				print( "using LAST uuid ["..grp.uuid.."]" )
			end
			if( grp.rev == "LAST" ) then
				if( grp.last_response ~= nil ) then
					if( grp.last_response.rev ~= nil ) then
						-- "create" action returns "rev"
						grp.rev = grp.last_response.rev
					elseif( grp.last_response._rev ~= nil ) then
						-- other actions return "_rev"
						grp.rev = grp.last_response._rev
					end
				end
				print( "using LAST rev ["..grp.rev.."]" )
			end
		end
	end
	
	function grp.initAuxdata()
		local ad = {}
		ad.headers = {}
		if( grp.sessionauth == "default" ) then
			-- no auth yet
		else
			--ad.headers["AuthSession"] = grp.sessionauth
			ad.headers["Cookie"] = grp.sessionauth
		end
		return ad
	end

	--
	-- user login/logout
	function grp.userLogin( xtra )
		grp.handleXtra( xtra )
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/_session"
		auxdata.headers["Content-Type"] = "application/x-www-form-urlencoded"
		auxdata.body = "username=" .. grp.username
			.. "&password=" .. grp.password
		return grp.CloudantWorker( "POST", url, auxdata )
	end
	function grp.userLogout( xtra )
		grp.handleXtra( xtra )
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/_session"
		return grp.CloudantWorker( "DELETE", url, auxdata )
	end
	function grp.userStatus( xtra )
		grp.handleXtra( xtra )
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/_session"
		return grp.CloudantWorker( "GET", url, auxdata )
	end


	--
	-- document objects
	function grp.createDocument( xtra )
		grp.handleXtra( xtra )
		if( grp.data == nil ) then
			grp.throwError( "No data specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		auxdata.headers["Content-Type"] = "application/json"
		auxdata.body = json.encode( grp.data )
		local url = grp.baseurl .. "/"
				.. grp.database
		local httpverb = "POST"
		return grp.CloudantWorker( httpverb, url, auxdata )
	end
	function grp.retrieveDocument( xtra )
		grp.handleXtra( xtra )
		if( grp.uuid == nil ) then
			grp.throwError( "No UUID specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database .. "/"
				.. grp.uuid
		return grp.CloudantWorker( "GET", url, auxdata )
	end
	function grp.updateDocument( xtra )
		grp.handleXtra( xtra )
		if( grp.uuid == nil ) then
			grp.throwError( "No UUID specified" )
			return
		elseif( grp.rev == nil ) then
			grp.throwError( "No REV specified" )
			return
		elseif( grp.data == nil ) then
			grp.throwError( "No data specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		auxdata.headers["Content-Type"] = "application/json"
		auxdata.headers["If-Match"] = grp.rev
		auxdata.body = json.encode( grp.data )
		local url = grp.baseurl .. "/"
				.. grp.database .. "/"
				.. grp.uuid
		return grp.CloudantWorker( "PUT", url, auxdata )
	end
	function grp.deleteDocument( xtra )
		grp.handleXtra( xtra )
		if( grp.uuid == nil ) then
			grp.throwError( "No UUID specified" )
			return
		elseif( grp.rev == nil ) then
			grp.throwError( "No REV specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		auxdata.headers["If-Match"] = grp.rev
		local url = grp.baseurl .. "/"
				.. grp.database .. "/"
				.. grp.uuid
		return grp.CloudantWorker( "DELETE", url, auxdata )
	end
	-- TODO: "info" action doesn't return id, so "LAST" doesn't work
	function grp.infoDocument( xtra )
		grp.handleXtra( xtra )
		if( grp.uuid == nil ) then
			grp.throwError( "No UUID specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database .. "/"
				.. grp.uuid
		return grp.CloudantWorker( "HEAD", url, auxdata )
	end

	function grp.listDocuments( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database .. "/_all_docs"
				
		-- TODO: other parameters could be included
		--    startkey/endkey, descending, limit, skip
		--    key= .. gives info sort of like "HEAD"
		if( xtra ~= nil ) then
			if( xtra.include_docs ~= nil ) then
				url = url .. "?include_docs=" .. tostring(xtra.include_docs)
			end
		end
		return grp.CloudantWorker( "GET", url, auxdata )	
	end

	function grp.createDocumentAttachment( xtra )
		grp.handleXtra( xtra )
		if( grp.uuid == nil ) then
			grp.throwError( "No UUID specified" )
			return
		end
		if( grp.file == nil ) then
			grp.throwError( "No data-file specified" )
			return
		end
		if( grp.rev == nil ) then
			grp.throwError( "No REV specified" )
			return
		end
		-- load the data file
		-- TODO: need to find a way to stream-read this??
		local path = system.pathForFile(  grp.file, system.CachesDirectory )
		local fp = io.open( path, "r" )
		local filedata = fp:read( "*a" )
		fp:close()
		-- post the data to the url
		local auxdata = grp.initAuxdata()
		auxdata.headers["Content-Type"] = "application/octet-stream"
		auxdata.headers["Content-Length"] = filedata:len()
		auxdata.headers["If-Match"] = grp.rev
		auxdata.body = filedata
		local url = grp.baseurl .. "/"
				.. grp.database .. "/" 
				.. grp.uuid .. "/"
				.. grp.file
		return grp.CloudantWorker( "PUT", url, auxdata )
	end
	function grp.retrieveDocumentAttachment( xtra )
		grp.handleXtra( xtra )
		if( grp.uuid == nil ) then
			grp.throwError( "No UUID specified" )
			return
		end
		if( grp.file == nil ) then
			grp.throwError( "No data-file specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database .. "/"
				.. grp.uuid .. "/"
				.. grp.file
		return grp.CloudantWorker( "GET", url, auxdata )
	end

	--
	-- database objects
	function grp.createDatabase( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database
		return grp.CloudantWorker( "PUT", url, auxdata )
	end
	function grp.retrieveDatabase( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database
		return grp.CloudantWorker( "GET", url, auxdata )
	end
	function grp.updateDatabase( xtra )
		return grp.throwError( "No way to update a database" )
	end
	function grp.deleteDatabase( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database
		return grp.CloudantWorker( "DELETE", url, auxdata )
	end
	function grp.listAllDatabases( xtra )
		grp.handleXtra( xtra )
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/_all_dbs"
		return grp.CloudantWorker( "GET", url, auxdata )
	end
	
	-- queries on database objects
	function grp.listAllIndices( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
			.. grp.database .. "/_index"
		return grp.CloudantWorker( "GET", url, auxdata )	
	end
	function grp.createIndex( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
			.. grp.database .. "/_index"
		auxdata.body = json.encode( grp.data )
		return grp.CloudantWorker( "POST", url, auxdata )	
	end
	function grp.retrieveIndex( xtra )
		return grp.throwError( "No way to retrieve an index (try query)" )
	end
	function grp.updateIndex( xtra )
		return grp.throwError( "No way to update an index" )
	end
	function grp.deleteIndex( xtra )
		return grp.throwError( "No way to delete an index" )
	end
	
	function grp.queryDatabase( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database .. "/_find"
		auxdata.body = json.encode( grp.query )
		print( "query ["..auxdata.body.."]" )
		return grp.CloudantWorker( "POST", url, auxdata )	
	end

	return grp
end


return Cloudant
