--[[
Copyright (c) 2013, Ricky Gall
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
    * Neither the name of <addon name> nor the
    names of its contributors may be used to endorse or promote products
    derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]


_addon.name = 'AEcho'
_addon.version = '2.02'
_addon.author = 'Nitrous (Shiva)'
_addon.command = 'aecho'

require('tables')
require('strings')
require('logger')
require('sets')
config = require('config')
chat = require('chat')
res = require('resources')

defaults = {}
defaults.buffs = S{	"light arts","addendum: white","penury","celerity","accession","perpetuance","rapture",
                    "dark arts","addendum: black","parsimony","alacrity","manifestation","ebullience","immanence",
                    "stun","petrified","silence","stun","sleep","slow","paralyze"
                }
defaults.alttrack = true
defaults.sitrack = true

settings = config.load(defaults)

autoecho = true

-- OPTIMIZATION: Build lowercase buff lookup for O(1) access instead of O(n) iteration
local buff_lookup = S{}

function rebuild_buff_lookup()
    buff_lookup = S{}
    for buff in settings.buffs:it() do
        buff_lookup:add(buff:lower())
    end
end

-- Build initial lookup table
rebuild_buff_lookup()

windower.register_event('gain buff', function(id)
    local buff = res.buffs[id]
    if not buff then return end
    
    local name = buff.english
    local name_lower = name:lower()
    
    -- OPTIMIZATION: O(1) lookup instead of O(n) iteration through settings.buffs
    if buff_lookup:contains(name_lower) then
        -- OPTIMIZATION: Cache player reference to avoid repeated API calls
        local player = windower.ffxi.get_player()
        if not player then return end
        
        local player_name = player.name
        
        -- Check for silence and auto-use echo drops
        if name_lower == 'silence' and autoecho then
            windower.send_command(string.format('input /item "Echo Drops" %s', player_name))
        end
        
        -- Send notification to other characters if enabled
        if settings.alttrack then
            windower.send_command(string.format('send @others atc %s - %s', player_name, name))
        end
    end
end)

windower.register_event('incoming text', function(_,new,color)
    -- OPTIMIZATION: Early exit if sitrack disabled (avoids pattern matching overhead)
    if not settings.sitrack then
        return new, color
    end
    
    -- OPTIMIZATION: Pattern matching only runs when needed
    -- Look for buff wear-off messages
    local match_start, match_end, effect_name = string.find(new, 'The effect of ([%w]+) is about to wear off.')
    
    if match_start then
        -- OPTIMIZATION: Cache player name and use string.format for efficiency
        local player = windower.ffxi.get_player()
        if player then
            windower.send_command(string.format('@send @others atc %s - %s wearing off.', player.name, effect_name))
        end
    end
    
    return new, color
end)

windower.register_event('addon command', function(...)
    local args = {...}
    if args[1] ~= nil then
        local comm = args[1]:lower()
        if comm == 'help' then
            local helptext = [[AEcho - Command List:
 1. aecho watch <buffname> --adds buffname to the tracker
 2. aecho unwatch <buffname> --removes buffname from the tracker
 3. aecho trackalt --Toggles alt buff/debuff messages on main (this requires send addon)
 4. aecho sitrack --When sneak/invis begin wearing passes this message to your alts
 5. aecho list --lists buffs being tracked
 6. aecho toggle --Toggles off automatic echo drop usage (in case you need this off. does not remain off across loads.)]]
            for _, line in ipairs(helptext:split('\n')) do
                windower.add_to_chat(207, line..chat.controls.reset)
            end
        elseif S{'watch','trackalt','unwatch','sitrack'}:contains(comm) then
            local list = ''
            local spacer = ''
            if comm == 'watch' then
                for i = 2, #args do
                    if i > 2 then spacer = ' ' end
                    list = list..spacer..args[i]
                end
                if settings.buffs[list] == nil then
                    settings.buffs:add(list:lower())
                    notice(list..' added to buffs list.')
                    -- OPTIMIZATION: Rebuild lookup table when buffs list changes
                    rebuild_buff_lookup()
                end
            elseif comm == 'unwatch' then
                for i = 2, #args do
                    if i > 2 then spacer = ' ' end
                    list = list..spacer..args[i]
                end
                if settings.buffs[list] ~= nil then
                    settings.buffs:remove(list:lower())
                    notice(list..' removed from buffs list.')
                    -- OPTIMIZATION: Rebuild lookup table when buffs list changes
                    rebuild_buff_lookup()
                end
            elseif comm == 'trackalt' then
                settings.alttrack = not settings.alttrack
            elseif comm == 'sitrack' then
                settings.sitrack = not settings.sitrack
            end
            settings:save()
        elseif comm == 'list' then
            settings.buffs:print()
        elseif comm == 'toggle' then
            autoecho = not autoecho
        else
            return
        end
    end
end)