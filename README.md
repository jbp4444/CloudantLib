CloudantLib
===========

Library to connect Corona SDK apps to Cloudant's web services

Includes:
* Asynchronous module -- uses Corona's network.request -- tries to keep track of the last UUID so you can easily trigger sequences of commands
* Command-Sequence module -- works with Async module so that you can queue up a sequence of commands and have them all execute in order; tries to track the last UUID using 'uuid="LAST"'


