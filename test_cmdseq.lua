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

local cloudant = require( "scripts.CloudantAsynchr" )
local cmdseq = require( "scripts.CommandSeq" )
local json = require( "json" )

for i=1,5 do
	print( " " )
end

--
--  --  --  --  --  --  --  --  --  --  --  --  --  --
--

-- handle the return-result and go to next command in sequence
function printResult( e )
	print( "cloudant result caught:" )
	print( "  isError = "..tostring(e.isError) )
	print( "  status = "..e.status )
	print( "  response = ["..e.response.."]" )
	print( "  respHeaders = ["..json.encode(e.responseHeaders).."]" )
end
print( "onComplete func is "..tostring(printResult) )

--
--  --  --  --  --  --  --  --  --  --  --  --  --  --
--

-- configure the connection to cloudant
local clobj = cloudant.new({
	baseurl = cloudant_baseurl,
	database = cloudant_database,
	username = cloudant_username,
	password = cloudant_password,
	-- onComplete will be overwritten by CommandSeq
	onComplete = printResult,
})

-- sequence of commands to run
local commandSeq = cmdseq.new( clobj, nil )

commandSeq.add( "login", clobj.userLogin, nil )

commandSeq.add( "userStatus", clobj.userStatus, nil )

if( document_tests ) then
	commandSeq.add({
		-- create a new object, retrieve it, then delete it
		{ "document-create", clobj.createDocument, {
			data = {
				foofoo = "foo",
				barbar = "bar",
				bazbaz = "baz",
			},
		} },
		{ "document-retrieve", clobj.retrieveDocument, {
			uuid = "LAST",
		} },
		-- TODO: "info" action doesn't return id, so "LAST" doesn't work
		--{ "document-info", clobj.infoDocument, {
		--	uuid = "LAST",
		--} },
		{ "document-update", clobj.updateDocument, {
			uuid = "LAST",
			rev = "LAST",
			data = {
				barbar = "newnewnewnew"
			},
		} },
		{ "document-delete", clobj.deleteDocument, {
			uuid = "LAST",
			rev = "LAST",
		} },
	})
end

if( database_tests ) then
	commandSeq.add({
		-- retrieve a list of all databases
		{ "database-list-all", clobj.listAllDatabases, nil },
	
		-- create a new object, retrieve it, then delete it
		{ "database-create", clobj.createDatabase, {
			database = "newcolls",
		} },
		{ "database-retrieve", clobj.retrieveDatabase, {
			database = "newcolls",
		} },
		{ "database-update", clobj.updateDatabase, {
			database = "newcolls",
		} },
		{ "database-delete", clobj.deleteDatabase, {
			database = "newcolls",
		} },
	})
end

if( attachment_tests ) then
	commandSeq.add({
		-- create a new object, retrieve it, then delete it
		{ "attach-document-create", clobj.createDocument, {
			uuid = "foobarfile",
			data = {
				mykey = "a_key",
				myval = "a_val",
			},
		} },
		{ "attachment-upload", clobj.createDocumentAttachment, {
			uuid = "foobarfile",
			rev = "LAST",
			file = "data.txt",
		} },
		{ "attachment-document-retrieve", clobj.retrieveDocument, {
			uuid = "foobarfile",
		} },
		{ "attachment-download", clobj.retrieveDocumentAttachment, {
			uuid = "foobarfile",
		} },
		{ "attach-document-delete", clobj.deleteDocument, {
			uuid = "foobarfile",
		} },
	
	})
end

if( query_tests ) then
	function inspectResults( tbl )
		print( "inspectResult caught:" )
		print_r( tbl )
		for k,v in pairs(tbl.clobj.last_response.docs) do
			print( "  ["..k.."] = ["..tostring(v).."]  "..
				"("..v._id..","..v._rev..")" )
			--print_r( v )
			commandSeq.insertBefore( "logout", 
				"query-document-delete",
				clobj.deleteDocument, {
					uuid = v._id,
					rev  = v._rev,
			} )
		end
	end
	
	commandSeq.add({
		-- create a new object, retrieve it, then delete it
		--{ "query-database-create", clobj.createDatabase, {
		--	database = "stuffs",
		--} },
		{ "query-list-indices", clobj.listAllIndices, nil },
		
		{ "query-index-create", clobj.createIndex, {
			data = {
				name = "mykey-idx",
				index = {
					fields = { "mykey" },
				},
			},
		} },

		{ "query-document-create", clobj.createDocument, {
			data = {
				mykey = "abc",
				myval = "123",
			},
		} },
		{ "query-document-create", clobj.createDocument, {
			data = {
				mykey = "abc",
				myval = "456",
			},
		} },
		{ "query-document-create", clobj.createDocument, {
			data = {
				mykey = "def",
				myval = "123",
			},
		} },
		{ "query-database-query1", clobj.queryDatabase, {
			query = {
				selector = {
					mykey = {
						["$eq"] = "abc",
					},
				},
			},
		} },
		{ "query-inspect-results", commandSeq.userFunction, {
			fcn  = inspectResults,
			args = {
				database = "stuff",
				query = "",
				clobj = clobj,
			}
		} },
		--{ "query-database-delete", clobj.deleteDatabase, {
		--	database = "stuff",
		--} },
	})
end

commandSeq.add( "logout", clobj.userLogout, nil )

commandSeq.exec()
