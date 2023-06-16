--[[ TODO:
    Check what kind of item opens the chest.
        Not sure which packets we'll need of these.
        We also need to make sure that we're capturing the packet out before we get our results back from the chat log.
        0x0032	Trade Request
        0x0033	Trade
        0x0034	Trade Window Item
        0x0036	Trade NPC
        Keep a running tab, for each tool/key type and each zone/chest/coffer.
        Keep a tab of success/failure/type of failure etc.
        Save this when we unload and set previous values when we load.
        For starters, just dump a log when user does /tt tab, or /tt results
    Add option for alphabetical sorting, time based (ascending/descending)
    If chest checked returns the floor of the current time for that chest, don't update it.
    Update new chest opens to include a range for the min illusion time, and max. Max should be 30m, min could be as 
        low as 25m from what I've seen.
  ]]

--[[ BUG:

  ]]