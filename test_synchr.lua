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

local cloudant = require( "scripts.CloudantLib" )
local json = require( "json" )

for i=1,5 do
	print( " " )
end

--
--  --  --  --  --  --  --  --  --  --  --  --  --  --
--

-- handle the return-result and go to next command in sequence
function execCommand( title, cmd, args )
	print( "running "..title.." command" )
	local e = cmd( args )
	print( "cloudant result caught:" )
	print( "  isError = "..tostring(e.isError) )
	print( "  status = "..e.status )
	print( "  response = ["..json.encode(e.response).."]" )
	--print( "  respHeaders = ["..json.encode(e.responseHeaders).."]" )
end
print( "onComplete func is "..tostring(execCommand) )

--
--  --  --  --  --  --  --  --  --  --  --  --  --  --
--

-- configure the connection to cloudant
local clobj = cloudant.new({
	synchronous = true,
	baseurl = cloudant_baseurl,
	database = cloudant_database,
	username = cloudant_username,
	password = cloudant_password,
})

execCommand( "login", clobj.userLogin, nil )

execCommand( "userStatus", clobj.userStatus, nil )

if( document_tests ) then
		-- create a new object, retrieve it, then delete it
	execCommand( "document-create", clobj.createDocument, {
			data = {
				foofoo = "foo",
				barbar = "bar",
				bazbaz = "baz",
			},
		} )
	execCommand( "document-retrieve", clobj.retrieveDocument, {
			uuid = "LAST",
		} )
	execCommand( "document-update", clobj.updateDocument, {
			uuid = "LAST",
			rev = "LAST",
			data = {
				barbar = "newnewnewnew"
			},
		} )
	execCommand( "document-delete", clobj.deleteDocument, {
			uuid = "LAST",
			rev = "LAST",
		} )
end

if( database_tests ) then
		-- retrieve a list of all databases
	execCommand( "database-list-all", clobj.listAllDatabases, nil )
	
		-- create a new object, retrieve it, then delete it
	execCommand( "database-create", clobj.createDatabase, {
			database = "newdb",
		} )
	execCommand( "database-retrieve", clobj.retrieveDatabase, {
			database = "newdb",
		} )
	execCommand( "database-update", clobj.updateDatabase, {
			database = "newdb",
		} )
	execCommand( "database-delete", clobj.deleteDatabase, {
			database = "newdb",
		} )
end

if( attachment_tests ) then
		-- create a new object, retrieve it, then delete it
	execCommand( "attach-document-create", clobj.createDocument, {
			uuid = "foobarfile",
			data = {
				mykey = "a_key",
				myval = "a_val",
			},
		} )
	execCommand( "attachment-upload", clobj.createDocumentAttachment, {
			uuid = "foobarfile",
			rev = "LAST",
			file = "data.txt",
		} )
	execCommand( "attachment-document-retrieve", clobj.retrieveDocument, {
			uuid = "foobarfile",
		} )
	execCommand( "attachment-download", clobj.retrieveDocumentAttachment, {
			uuid = "foobarfile",
		} )
	execCommand( "attach-document-delete", clobj.deleteDocument, {
			uuid = "foobarfile",
		} )
end

if( query_tests ) then	
	function printQueryResults( title, cl )
		print( "running "..title.." command" )
		for k,v in pairs(cl.last_response.docs) do
			print( "  ["..k.."] = [" .. json.encode(v) .. "]" )
		end
	end
	
		-- create a new object, retrieve it, then delete it
	execCommand( "query-list-indices", clobj.listAllIndices, nil )
		
	execCommand( "query-index-create", clobj.createIndex, {
			data = {
				name = "mykey-idx",
				index = {
					fields = { "mykey" },
				},
			},
		} )

	execCommand( "query-document-create1", clobj.createDocument, {
			data = {
				mykey = "abc",
				myval = "123",
			},
		} )
	execCommand( "query-document-create2", clobj.createDocument, {
			data = {
				mykey = "abc",
				myval = "456",
			},
		} )
	execCommand( "query-document-create3", clobj.createDocument, {
			data = {
				mykey = "def",
				myval = "123",
			},
		} )
	execCommand( "list-all-docs", clobj.listDocuments, {
		include_docs = true,
	} )
	execCommand( "query-database-query1", clobj.queryDatabase, {
			query = {
				selector = {
					mykey = {
						["$eq"] = "abc",
					},
				},
			},
		} )
	printQueryResults( "inspect query results:", clobj )

	execCommand( "query-database-query2", clobj.queryDatabase, {
			query = {
				selector = {
					myval = {
						["$eq"] = "123",
					},
				},
			},
		} )

	-- clean up
	print( "cleaning up query documents" )
	local rtn = clobj.listDocuments()
	for k,v in pairs(rtn.response.rows) do
		print( "  ["..k.."] = [" .. json.encode(v) .. "]" )
		execCommand( "deleting item "..k, clobj.deleteDocument, {
			uuid = v.id,
			rev = v.value.rev,
		})
	end

end

execCommand( "logout", clobj.userLogout, nil )
