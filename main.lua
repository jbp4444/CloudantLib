--
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

-- the username file just has two global vars defined:
--   cloudant_baseurl = "https://foo.bar.com"
--   cloudant_database = "mydatabase"
--   cloudant_username = "foo"
--   cloudant_password = "barbaz"
require( "cloudantInfo" )

-- what test-environment to run?
synchr_tests = true
asynchr_tests = false  -- only login/logout are testable for asynchr
cmdseq_tests = false   -- ... use cmdseq instead
-- what test-sets to run?
document_tests = true
database_tests = false
attachment_tests = false
query_tests = true

--
--  --  --  --  --  --  --  --  --  --  --  --  --  --
--

function print_r ( t ) 
        local print_r_cache={}
        local function sub_print_r(t,indent)
                if ( print_r_cache[tostring(t)]) then
                        print(indent.."*"..tostring(t))
                else
                        if (type(t)=="table") then
	                        print_r_cache[tostring(t)]=true
                            for pos,val in pairs(t) do
                                    if (type(val)=="table") then
                                            print(indent.."["..pos.."] => "..tostring(t).." {")
                                            --sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
                                            sub_print_r(val,indent.."  ")
                                            --print(indent..string.rep(" ",string.len(pos)+6).."}")
                                            print(indent.."}")
                                    elseif (type(val)=="string") then
                                            print(indent.."["..pos..'] => "'..val..'"')
                                    else
                                            print(indent.."["..pos.."] => "..tostring(val))
                                    end
                            end
                        else
                                print(indent..tostring(t))
                        end
                end
        end -- end of function
        if (type(t)=="table") then
                print(tostring(t).." {")
                sub_print_r(t,"  ")
                print("}")
        else
                sub_print_r(t,"  ")
        end
        print()
end

--
--  --  --  --  --  --  --  --  --  --  --  --  --  --
--

if( file_tests ) then
	-- create the file data.txt
	local path = system.pathForFile(  "data.txt", system.CachesDirectory )
	local fp = io.open( path, "w" )
	for i=1,10 do
		fp:write( "Hello World " )
	end
	fp:close()
end

--
--  --  --  --  --  --  --  --  --  --  --  --  --  --
--

-- run the synchronous (socket.http/ltn12) tests?
if( synchr_tests ) then
	require( "test_synchr" )
end

-- run the asynchronous (network.request) tests?
if( asynchr_tests ) then
	require( "test_asynchr" )
end

-- run the command-sequence helper for asynchronous tests?
if( cmdseq_tests ) then
	require( "test_cmdseq" )
end
