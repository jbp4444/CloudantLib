-- test code for running Corona against cloudant cloud resources
--
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

--
-- NOTE: the callback nature of the asynchr calls makes it difficult
-- to lay out sets of tests to perform (they'd all have to be chained).
-- The CommandSeq module does exactly that and uses the same underlying
-- Asynchr lib ... so running the CommandSeq tests will perform all the
-- same unit-tests that a "full" asynchr test-set would perform.
--

local cloudant = require( "scripts.CloudantLib" )
local json = require( "json" )

for i=1,5 do
	print( " " )
end

--
--  --  --  --  --  --  --  --  --  --  --  --  --  --
--

-- configure the connection to cloudant
local clobj = cloudant.new({
	baseurl = cloudant_baseurl,
	database = cloudant_database,
	username = cloudant_username,
	password = cloudant_password,
	-- onComplete will be overwritten later
	--onComplete = "default"
})

-- handle the login-result and initiate the logout command
function handleLogout( e )
	print( "cloudant logout result caught:" )
	print( "  isError = "..tostring(e.isError) )
	print( "  status = "..e.status )
	print( "  response = ["..e.response.."]" )
	print( "  respHeaders = ["..json.encode(e.responseHeaders).."]" )
end

-- handle the login-result and initiate the logout command
function handleLogin( e )
	print( "cloudant login result caught:" )
	print( "  isError = "..tostring(e.isError) )
	print( "  status = "..e.status )
	print( "  response = ["..e.response.."]" )

	clobj.userLogout({
		onComplete = handleLogout,
	})	
end

-- could specify username/password here
clobj.userLogin({
	onComplete = handleLogin,
})
