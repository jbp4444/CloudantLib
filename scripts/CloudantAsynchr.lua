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
				if( respHdrs["Set-Cookie"] ~= nil ) then
					print( "found a response cookie" )
					grp.sessionauth = respHdrs["Set-Cookie"]
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

	function grp.CloudantWorker( httpverb, url, auxdata )
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
		
		network.request( url, httpverb, grp.baseNetworkListener, auxdata )
	end

	-- TODO: may need to put this behind timer.performWithDelay
	-- or else main thread will throw error/onComplete func before
	-- the program ever had a chance to respond 
	function grp.throwError( resp )
		local ee = {
			name = "CloudantResponse",
			target = grp,
			isError = true,
			status = 400,
			response = resp,
		}		
		if( grp.onComplete ~= nil ) then
			grp.onComplete( ee )
		end
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
			ad.headers["AuthSession"] = grp.sessionauth
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
		grp.CloudantWorker( "POST", url, auxdata )
	end
	function grp.userLogout( xtra )
		grp.handleXtra( xtra )
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/_session"
		grp.CloudantWorker( "DELETE", url, auxdata )
	end
	function grp.userStatus( xtra )
		grp.handleXtra( xtra )
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/_session"
		grp.CloudantWorker( "GET", url, auxdata )
	end


	--
	-- data-items (entities) objects
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
		if( grp.uuid ~= 0 ) then
			httpverb = "PUT"
			url = url .. "/" .. grp.uuid
		end
		grp.CloudantWorker( httpverb, url, auxdata )
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
		grp.CloudantWorker( "GET", url, auxdata )
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
		grp.CloudantWorker( "PUT", url, auxdata )
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
		grp.CloudantWorker( "DELETE", url, auxdata )
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
		grp.CloudantWorker( "HEAD", url, auxdata )
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
		grp.CloudantWorker( "PUT", url, auxdata )
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
		grp.CloudantWorker( "GET", url, auxdata )
	end

	--
	-- database objects
	function grp.createDatabase( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		-- TODO: check that database is pluralized
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database
		grp.CloudantWorker( "PUT", url, auxdata )
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
		grp.CloudantWorker( "GET", url, auxdata )
	end
	function grp.updateDatabase( xtra )
		grp.throwError( "No way to update a database" )
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
		grp.CloudantWorker( "DELETE", url, auxdata )
	end
	function grp.listAllDatabases( xtra )
		grp.handleXtra( xtra )
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/_all_dbs"
		grp.CloudantWorker( "GET", url, auxdata )
	end
	
	-- queries on database objects
	function grp.listAllIndices( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		-- TODO: check that database is pluralized
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
			.. grp.database .. "/_index"
		grp.CloudantWorker( "GET", url, auxdata )	
	end
	function grp.createIndex( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		-- TODO: check that database is pluralized
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
			.. grp.database .. "/_index"
		auxdata.body = json.encode( grp.data )
		grp.CloudantWorker( "POST", url, auxdata )	
	end
	function grp.retrieveIndex( xtra )
		grp.throwError( "No way to retrieve an index (try query)" )
	end
	function grp.updateIndex( xtra )
		grp.throwError( "No way to update an index" )
	end
	function grp.deleteIndex( xtra )
		grp.throwError( "No way to delete an index" )
	end
	function grp.queryDatabase( xtra )
		grp.handleXtra( xtra )
		if( grp.database == nil ) then
			grp.throwError( "No database specified" )
			return
		end
		-- TODO: check that database is pluralized
		local auxdata = grp.initAuxdata()
		local url = grp.baseurl .. "/"
				.. grp.database .. "/_find"
		auxdata.body = json.encode( grp.query )
		print( "query ["..auxdata.body.."]" )
		grp.CloudantWorker( "POST", url, auxdata )	
	end


	return grp
end


return Cloudant
