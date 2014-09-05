ApigeeLib
=========

Library to connect Corona SDK apps to Apigee's web services

Includes:
* Synchronous module -- uses socket.http and ltn12 -- good for (non-Corona) scripting or when you need the result from one command to feed into another command
* Asynchronous module -- uses Corona's network.request -- tries to keep track of the last UUID so you can easily trigger sequences of commands
* Command-Sequence module -- works with Async module so that you can queue up a sequence of commands and have them all execute in order; tries to track the last UUID using 'uuid="LAST"'


