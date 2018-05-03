--- 
-- @author Valery Zakharov <va13ak@gmail.com>
-- @date 2018-04-18 15:54:27

    local bit = require "plugin.bit"    
    local socket = require "socket"
    local qrencode = require "qrencode" -- http://speedata.github.io/luaqrcode/

    local bnot = bit.bnot
    local band, bor, bxor = bit.band, bit.bor, bit.bxor
    local lshift, rshift, rol = bit.lshift, bit.rshift, bit.rol

    -- was ported to lua by va13ak

    -- taken from http://servermule.webbtide.com/escpos.html
    -- http://servermule.webbtide.com/escpos.jar

    -- Portions of this code taken from http://new-grumpy-mentat.blogspot.coescPosPrinter.au/2014/06/java-escpos-image-printing.html
 
    local NUL = 0       -- Null
    local LF = 10       -- Line Feed
    local FF = 12       -- Form Feed
    local DLE = 16      -- data link escape character
    local DC1 = 17      -- device control 1 character 
    local ESC = 27      -- Escape
    local GS = 29       -- Group Separator

    local escPosPrinter = {
    }

    escPosPrinter.NUL = NUL
    escPosPrinter.LF  = LF
    escPosPrinter.FF  = FF
    escPosPrinter.DLE = DLE
    escPosPrinter.DC1 = DC1
    escPosPrinter.ESC = ESC
    escPosPrinter.GS  = GS

    -- see https://reference.epson-biz.com/modules/ref_escpos/index.php?content_id=72#

    escPosPrinter.INIT = { ESC, '@' }

    escPosPrinter.CUT_PAPER = { GS, 'V', 0 }
    escPosPrinter.FEED_PAPER_AND_CUT = { GS, 'V', 66, 0 }

    escPosPrinter.EMPHASIZED_MODE_ON = { ESC, '%', 1 }
    escPosPrinter.EMPHASIZED_MODE_OFF = { ESC, '%', 0 }

    escPosPrinter.DOUBLESTRIKE_MODE_ON = { ESC, 'G', 1 }
    escPosPrinter.DOUBLESTRIKE_MODE_OFF = { ESC, 'G', 0 }

    escPosPrinter.ALIGN_LEFT = { ESC, 'a', '0' }
    escPosPrinter.ALIGN_CENTER = { ESC, 'a', '1' }
    escPosPrinter.ALIGN_RIGHT = { ESC, 'a', '2' }

    escPosPrinter.UPSIDE_ON = { ESC, '{', 1 }
    escPosPrinter.UPSIDE_OFF = { ESC, '{', 0 }

    escPosPrinter.SELECT_BIT_IMAGE_MODE = { ESC, '*', 33 }
    escPosPrinter.SELECT_PAGE_MODE = { ESC, 'L' }
    escPosPrinter.SELECT_STANDARD_MODE = { ESC, 'S' }

    escPosPrinter.SET_LINE_SPACING_18 = { ESC, '3', 18 }
    escPosPrinter.SET_LINE_SPACING_24 = { ESC, '3', 24 }
    escPosPrinter.SET_LINE_SPACING_30 = { ESC, '3', 30 }
    escPosPrinter.SET_LINE_SPACING_DEFAULT = { ESC, '2' }

    escPosPrinter.UNDERLINED_OFF = { ESC, '-', 0 }
    escPosPrinter.UNDERLINED_NORMAL = { ESC, '-', 1 }
    escPosPrinter.UNDERLINED_EMPHASISED = { ESC, '-', 2 }

    escPosPrinter.SELECT_FONT_A = { ESC, 'M', 0 }
    escPosPrinter.SELECT_FONT_B = { ESC, 'M', 1 }
    escPosPrinter.SELECT_FONT_C = { ESC, 'M', 2 }

    escPosPrinter.NORMAL_HEIGHT = { GS, '!', 0x0 }
    escPosPrinter.DOUBLE_HEIGHT = { GS, '!', 0x1 }
    escPosPrinter.DOUBLE_HEIGHT_DOUBLE_WIDTH = { GS, '!', 0x11 }

    escPosPrinter.SELECT_FONT_NORMAL = { ESC, '!', 0x0 }
    escPosPrinter.SELECT_FONT_EMPHASISED = { ESC, '!', 0x8 }
    escPosPrinter.SELECT_FONT_DOUBLE_HEIGHT = { ESC, '!', 0x10 }
    escPosPrinter.SELECT_FONT_DOUBLE_WIDTH = { ESC, '!', 0x20 }
    escPosPrinter.SELECT_FONT_UNDERLINE = { ESC, '!', 0x80 }

    escPosPrinter.SET_BAR_CODE_HEIGHT = { GS, 'h', 100 }
    escPosPrinter.PRINT_BAR_CODE_1 = { GS, 'k', 2 }

    escPosPrinter.SELECT_PRINT_SHEET = { ESC, 'c', 48, 2 }
    escPosPrinter.SELECT_CYRILLIC_CHARACTER_CODE_TABLE = { ESC, 't', 17 }

    escPosPrinter.TRANSMIT_DLE_PRINTER_STATUS = { DLE, 4, 1 }
    escPosPrinter.TRANSMIT_DLE_OFFLINE_PRINTER_STATUS = { DLE, 4, 2 }
    escPosPrinter.TRANSMIT_DLE_ERROR_STATUS = { DLE, 4, 3 }
    escPosPrinter.TRANSMIT_DLE_ROLL_PAPER_SENSOR_STATUS = { DLE, 4, 4 }

    
    --[[
    /**
     * Defines if a color should be printed (burned).
     *
     * @param color RGB color.
     * @return true if should be printed/burned (black), false otherwise
     * (white).
     */
    --]]
    function escPosPrinter:shouldPrintColor( color )
        if self.treatPixelAsBlack then
            return self.treatPixelAsBlack( color )
        end

        local threshold = 127
        local a, r, g, b, luminance
        a = band( rshift( color, 24 ), 0xff )
        if (a ~= 0xff) then -- ignore pixels with alpha channel
            return false
        end
        r = band( rshift( color, 16 ), 0xff )
        g = band( rshift( color, 8 ), 0xff )
        b = band( color, 0xff )

        luminance = math.floor( 0.299 * r + 0.587 * g + 0.114 * b )

        return luminance < threshold
    end

    --[[
    /**
     * Gets the pixels stored in an image. TODO very slow, could be improved
     * (use different class, cache result, etc.)
     * 
     * This is used by bit-image print
     *
     * @param image image to get pixels froescPosPrinter.
     * @return 2D array of pixels of the image (RGB, row major order)
     */
     --]]
    local function getPixelsSlow( image, ... )
        local mult = arg[1] or 1        -- multiplexor
        local width = #image or 0       -- image width
        local height = #image[1] or 0   -- image height
        local result = {}
        if ( mult == 1 ) then
            for row = 1, height do
                result[row] = {}
                for col = 1, width do
                    result[row][col] = image[col][row]
                end
            end
        else
            width = width * mult
            height = height * mult
            for row = 1, height do
                result[row] = {}
                for col = 1, width do
                    result[row][col] = image[math.ceil( col/mult )][math.ceil( row/mult )]
                end
            end
        end
        return result
    end

    --[[
    /**
     * Rasterize an image for storing in NV RAM
     * 
     * @param image
     * @return 
     */
    --]]
    function escPosPrinter:rasterizeImage( image, ... )
        local mult = arg[1] or 1
        local width = (#image[1] or 0) * mult
        local height = (#image or 0) * mult
        local z = math.floor( width / 8 )
        if (z * 8 < width) then
            z = z + 1
        end
        local result = {}
        for row = 1, height do
            for col = 1, width, 8 do
                local slice = 0

                for b = 1, 8 do 
                    local colb = col + b - 1
                    local bx = 0
                    if colb <= width then
                        if ( mult == 1 ) then
                            bx = image[colb][row]
                        else
                            bx = image[math.ceil( colb/mult )][math.ceil( row/mult )]
                        end
                    end
                    local v = self:shouldPrintColor( bx )
                    slice = bor( slice, lshift( ( v and 1 or 0), (1 + 7 - b) ) )
                end

                result[#result + 1] = slice
            end
        end
        return result
    end

    --[[
    /**
     * Collect a slice of 3 bytes with 24 dots for image printing.
     *
     * @param y row position of the pixel.
     * @param x column position of the pixel.
     * @param img 2D array of pixels of the image (RGB, row major order).
     * @return 3 byte array with 24 dots (field set).
     */
    --]]
    function escPosPrinter:collectSlice( y, x, img )
        local slices = { 0, 0, 0 }
        local yy = y
        local i = 1
        while ( ( yy <= y + 24 ) and ( i <= 3 ) ) do
            local slice = 0

            for b = 1, 8 do
                local yyy = yy + b - 1
                if (yyy <= #img) then
                    local col = img[yyy][x]
                    local v = self:shouldPrintColor( col )
                    --print( "shouldPrintColor(", col, "): ", v and 1 or 0)
                    slice = bor( slice, lshift( ( v and 1 or 0), (7 - b + 1) ) )
                end
            end

            slices[i] = slice

            yy = yy + 8
            i = i + 1
        end

        return slices;
    end

    local function byteArrayToString ( byteArray, ... )
        local startPos = arg[1] and ( ( ( arg[1] - 1 ) % #byteArray) + 1) or 1;
        local endPos = arg[2] and ( ( ( arg[2] - 1 ) % #byteArray) + 1) or #byteArray;
        print ( unpack( byteArray ) )
        local str = string.char( unpack( byteArray ) );
        return str:sub( startPos, endPos );
    end


    function escPosPrinter:connect( ... )
        if self.client then
            if pcall( self.client.getstats, self.client ) then
                return true
            end
        end

        local host = arg[1] or self.host or "127.0.0.1"
        local port = arg[2] or self.port or 9100
        print( "----- connecting to "..tostring( port ).." on "..tostring( host ) )
        --client = socket.connect( host, port )
        self.client = socket.tcp()
        self.client:settimeout( connectionTimeout )
        return self.client:connect( host, port )
    end



    function escPosPrinter:new( ... )
        if (tostring(arg[1]) or ""):find("tcp{client}") then
            newObj = { client = arg[1] }
        else
            newObj = { host=arg[1], port=arg[2] }
        end
        -- set up newObj
        self.__index = self
        return setmetatable(newObj, self)
    --  newObject = { host=arg[1], port=arg[2] };
    --  self.__index = self;
    --  setmetatable( newObject, self );
    --  newObject:init( ... );
    --  return newObject;
    end

    function escPosPrinter:print( ... )
        for i, v in ipairs( arg ) do
            vtype = type( v )
            if vtype == "string" then
                self.client:send( v )
                --print( "'"..v.."'")
            elseif vtype == "number" then
                self.client:send( string.char( v ) )    -- temporary
                --print( "("..v..")")
            elseif vtype == "table" then
                --print( v )
                --print( unpack( v ) )
                self:print( unpack( v ) )
            else
                self.client:send( tostring( v ))
                --print( "'"..v.."'")
            end
        end
    end


    --[[
    /**
     * Close output stream
     * 
     * @throws IOException
     */
    public void close() throws IOException {
        writer.close();
    }
    --]]
    function escPosPrinter:close( ... )
        self.client:close()
    end

    --[[
    /**
     * Prints an image in bit-image mode
     * 
     * @param image
     * @throws IOException
     */
    --]]
    function escPosPrinter:printImage( image, ... )
        local pixels = getPixelsSlow( image, arg[1] )
        --print("----------getPixelsSlow")
        for i = 1, #pixels do
            str = ""
            for j = 1, #pixels[i] do        -- prints each "row" of the QR code on a line, one at a time
                local val = pixels[i][j]
                if val > 0 then
                    str = str.."1"
                elseif val < 0 then
                    str = str.." "
                else
                    str = str.."X"
                end
            end
            --print(str)
        end

        self:print( self.SET_LINE_SPACING_24 )

        --for (int y = 0; y < pixels.length; y += 24) {
        for y = 1, #pixels, 24 do

            self:print( self.SELECT_BIT_IMAGE_MODE ) -- bit mode
            self:print( band( 0x00ff, #pixels[y] ), rshift( band( 0xff00, #pixels[y] ), 8 ) )   -- width, low & high

            --for (int x = 0; x < pixels[y].length; x++) {
            for x = 1, #pixels[y] do
                -- For each vertical line/slice must collect 3 bytes (24 bits)
                self:print( self:collectSlice(y, x, pixels) )
            end
            self:print( LF )
        end
        self:print( self.SET_LINE_SPACING_30 )
    end

    --[[
    /**
     * prints image stored in NV RAM - note image is stored as "G1"
     * 
     * @throws IOException
     */
    --]]
    function escPosPrinter:printNVImage( ... )
        if arg[1] then
            self:uploadNVImage( arg[1], arg[2] )
        end

        -- Set graphics data: [Function 69] Print the specified NV graphics
        -- data. Prints data that corresponds to key code "G1" at 1x1 size. GS (
        -- L pL pH m fn kc1/Kc2 x y GS "(L" 6 0 48 69 "G1" 1 1
        self:print( GS, '(', 'L', 6, 0, 48, 69, 'G', '1', 1, 1 )
    end

    --[[
    /**
     * Send image to the printer
     * Image is stored in NV RAM
     * Note: for large images may need to use GS 8 L command
     *
     * @param image
     * @throws java.io.IOException
     */
     --]]
    function escPosPrinter:uploadNVImage( image, ... )
        local mult = arg[1] or 1
        local pixels = self:rasterizeImage( image, mult )

        local w = (#image or 0) * mult      -- image height
        local h = (#image[1] or 0) * mult   -- image width

        local xH = math.floor( w / 256 )
        local xL = w - 256 * xH

        local yH = math.floor( h / 256 )
        local yL = h - 256 * yH

        local p = #pixels + 11       -- 11 = one byte each for m, fn, a, kc1/kc2, b, xL, xH, yL, yH, c
        local pH = math.floor( p / 256 )
        local pL = p - pH * 256

        -- delete previous NV data
        self:print( GS, '(', 'L', 4, 0, 48, 66, 'G', '1' )

        -- set NV data
        self:print( GS, '(', 'L', pL, pH, 48, 67, 48, 'G', '1', 1, xL, xH, yL, yH, 49 )

        self:print( pixels )
    end


    function escPosPrinter:printQRImage( ... )
        local data = arg[1] or ""
        local size = arg[2] or 5
        local ec_level = arg[3] or 0
        if type( arg[2] ) == "table" then
            size = arg[2].size or size
            ec_level = arg[2].ec_level or ec_level
        end

        local ok, tab_or_message = qrencode.qrcode( data, ec_level )
        if not ok then
            print(tab_or_message)

        else
            local bkupTreatPixelAsBlack = self.treatPixelAsBlack
            self.treatPixelAsBlack = function ( x ) return (x > 0) end

            self:printImage( tab_or_message, size )

            self.treatPixelAsBlack = bkupTreatPixelAsBlack
        end
    end

    function escPosPrinter:printQRNVImage( ... )
        local data = arg[1] or ""
        local size = arg[2] or 5
        local ec_level = arg[3] or 0
        if type( arg[2] ) == "table" then
            size = arg[2].size or size
            ec_level = arg[2].ec_level or ec_level
        end

        local ok, tab_or_message = qrencode.qrcode( data, ec_level )
        if not ok then
            print(tab_or_message)

        else
            local bkupTreatPixelAsBlack = self.treatPixelAsBlack
            self.treatPixelAsBlack = function ( x ) return (x > 0) end

            self:printNVImage( tab_or_message, size )

            self.treatPixelAsBlack = bkupTreatPixelAsBlack
        end

    end

    function escPosPrinter:printQR( ... )
        local data = arg[1] or ""
        local size = arg[3] or 5
        local ec_level = arg[4] or 0
        local print_method = arg[2] or 0
        if type( arg[2] ) == "table" then
            size = arg[3].size or size
            ec_level = arg[4].ec_level or ec_level
            print_method = arg[2].print_method or print_method
        end

        if print_method == 1 then
            return self:printQRNVImage( data, size, ec_level )

        elseif print_method == 2 then
            return self:printQRImage( data, size, ec_level )
        end

        -- taken from https://stackoverflow.com/a/29221432

        local p = #data + 3
        local pL = p % 256
        local pH = math.floor( p / 256 )
    
        -- QR Code: Select the model
        --              Hex     1D      28      6B      04      00      31      41      n1(x32)     n2(x00) - size of model
        -- set n1 [49 x31, model 1] [50 x32, model 2] [51 x33, micro qr code]
        -- https://reference.epson-biz.com/modules/ref_escpos/index.php?content_id=140
        self:print( 0x1d, 0x28, 0x6b, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00 )
    
        -- QR Code: Set the size of module
        -- Hex      1D      28      6B      03      00      31      43      n
        -- n depends on the printer
        -- https://reference.epson-biz.com/modules/ref_escpos/index.php?content_id=141
        --
        -- Размер в символах!!! - не совсем так, здесь размер - просто множитель размера точки :)
        self:print( 0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x43, size )
    
    
        --          Hex     1D      28      6B      03      00      31      45      n
        -- Set n for error correction [48 x30 -> 7%] [49 x31-> 15%] [50 x32 -> 25%] [51 x33 -> 30%]
        -- https://reference.epson-biz.com/modules/ref_escpos/index.php?content_id=142
        self:print( 0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x45, 0x30 + ec_level )
    
    
        -- QR Code: Store the data in the symbol storage area
        -- Hex      1D      28      6B      pL      pH      31      50      30      d1...dk
        -- https://reference.epson-biz.com/modules/ref_escpos/index.php?content_id=143
        --                        1D          28          6B         pL          pH  cn(49->x31) fn(80->x50) m(48->x30) d1…dk
        self:print( 0x1d, 0x28, 0x6b, pL, pH, 0x31, 0x50, 0x30 )
    
        -- data
        self:print( data )
    
        -- QR Code: Print the symbol data in the symbol storage area
        -- Hex      1D      28      6B      03      00      31      51      m
        -- https://reference.epson-biz.com/modules/ref_escpos/index.php?content_id=144
        self:print( 0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x51, 0x30 )
    end

    return escPosPrinter