--
--   Copyright 2013-2014 John Pormann
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

local CommandSeq = {}

function CommandSeq.new( clObj, params )
	local csObj = {}
	csObj.cloudObj = clObj
	csObj.seq = {}
	csObj.onComplete = function(e)
			print( "default ComandSeq.onComplete function called" )
		end

	-- send an event back to the caller
	local function callbackToUser( e )
		-- TODO: check for name, isError, status, response
		--print( "calling user onComplete func "..tostring(csObj.userOnComplete) )
		if( csObj.userOnComplete ~= nil ) then
			csObj.userOnComplete( e )
		end
	end	

	local function catchCloudResult( e )
		-- TODO: have a user-option for progress/no-progress
		callbackToUser( e )
				
		-- see if there are more commands in this sequence
		if( table.getn(csObj.seq) <= 0 ) then
			print( "no more commands to run" )
			callbackToUser({
				name = "CommandSeqResponse",
				isError = false,
				status = 9900,
				response = "Sequence complete",
			})
		else
			csObj.exec()
		end
	end
	
	function csObj.userFunction( tbl )
		print( "found a userfunc call" )
		local f = tbl.fcn
		local x = tbl.args
		print( "  f = ["..tostring(f).."]" )
		f( x )
		catchCloudResult( {
			name = "CommandSeqResponse",
			isError = false,
			status = 8800,
			response = "userFunction called",
		} )
	end
 	
	function csObj.exec()
		-- TODO: make sure onComplete funcs (cloudObj and cmdSeq) 
		-- are configured properly
		local tfx = table.remove( csObj.seq, 1 )
		local t = tfx[1]
		local f = tfx[2]
		local x = tfx[3]
		-- save the user's onComplete function, even if nil
		if( x == nil ) then
			x = {}
		else
			-- if present, intercept the user's onComplete func
			if( x.onComplete ~= nil ) then
				--print( "saving user's onComplete func" )
				csObj.userOnComplete = x.onComplete
			end
		end
		-- we need to intercept the onComplete handler
		x.onComplete = catchCloudResult
		print( "running "..t.." command" )
		--print( "  onComplete = "..tostring(x.onComplete) )
		--print( "  user onComplete = "..tostring(csObj.userOnComplete) )
		--print( "  f = ["..tostring(f).."]" )
		--print( "  x = ["..tostring(x).."]" )
		--print_r( x )
		f( x )
	end

	function csObj.add( txt, cmd, opts )
		-- TODO: check args/list for validity
		if( type(txt) == "table" ) then
			-- assume this is a list of commands to add
			for i,j in ipairs(txt) do
				table.insert( csObj.seq, j )
			end
		else
			-- just one command to add
			table.insert( csObj.seq, {txt,cmd,opts} )
		end
	end
	
	function csObj.insertBefore( keyname, txt, cmd, opts )
		print( "inserting command before ("..keyname..")" )
		-- first, find the keyname to insert near
		local keyidx = -1
		for i,v in ipairs(csObj.seq) do
			if( v[1] == keyname ) then
				print( "found key ["..keyname.."] at i="..i )
				keyidx = i
				break
			end
		end
		
		if( keyidx <= 0 ) then
			-- error
			print( "Error - could not find key ["..keyname.."]" )
		else
			-- TODO: check args/list for validity
			if( type(txt) == "table" ) then
				-- assume this is a list of commands to add
				for i,j in ipairs(txt) do
					table.insert( csObj.seq, keyidx+i-1, j )
				end
			else
				-- just one command to add
				table.insert( csObj.seq, keyidx, {txt,cmd,opts} )
			end
		end
	end

	--
	-- initialize the cmdseq object
	--
	
	-- check for user-params
	if( params ~= nil ) then
		-- ok if onComplete is nil/unspecified
		csObj.userOnComplete = params.onComplete
	end
	
	-- if no onComplete func is given, take it from the cloud-obj
	if( csObj.userOnComplete == nil ) then
		csObj.userOnComplete = clObj.onComplete
	end
	
	--print( "user-onComplete func is "..tostring(csObj.userOnComplete) )
	--print( "override onComplete func with "..tostring(catchCloudResult) )
	
	return csObj
end

return CommandSeq
