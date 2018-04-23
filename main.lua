--- 
-- @author Valery Zakharov <va13ak@gmail.com>
-- @date 2018-04-18 10:00:09

local socket = require "socket"
local qrencode = require "qrencode"
local escposprint = require "escposprint"


local port = 9100
local host = "10.10.10.3"
local connectionTimeout = 5
local ioTimeout = 5

local printer = escposprint:new( host, port )

local codeword = "The quick brown fox jumps over the lazy dog.\r\nСпритна бура лисиця стрибає через ледачого собаку"
if codeword then
    local ok, tab_or_message = qrencode.qrcode(codeword)
    if not ok then
        print(tab_or_message)
    else
        --local rows = {}
        --rows = matrix_to_string(tab_or_message,padding,padding_char,white_pixel,black_pixel)
        for i = 1, #tab_or_message do
            str = ""
            for j = 1, #tab_or_message[i] do        -- prints each "row" of the QR code on a line, one at a time
                local val = tab_or_message[i][j]
                if val > 0 then
                    str = str..tostring(val)
                elseif val < 0 then
                    str = str..tostring(10+val)
                else
                    str = str.."X"
                end
            end
            print(str)
        end
        if printer:connect() then
            printer.treatPixelAsBlack = function ( x ) return (x > 0) end

            printer:print( "print image", escposprint.LF )
            printer:printImage( tab_or_message, 5 )

            printer:print( "print NV image", escposprint.LF )
            printer:printNVImage( tab_or_message, 5 )

            printer:print( "print QR", escposprint.LF )
            printer:printQR( codeword )
            --[[
            for i = 1, 4 do
                printer:print( escposprint.LF )
            end
            --]]
            printer:print( escposprint.FEED_PAPER_AND_CUT )
        end
        --]]
    end
end
