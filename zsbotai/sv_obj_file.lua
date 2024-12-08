-- Written by Marco, additional serialization helper functions.

local meta = FindMetaTable("File")

local bit_band = bit.band
local bit_bor = bit.bor
local bit_rshift = bit.rshift
local bit_lshift = bit.lshift

local f_WriteByte = meta.WriteByte
local f_ReadByte = meta.ReadByte
local f_Read = meta.Read
local f_Write = meta.Write
local f_ReadFloat = meta.ReadFloat
local f_WriteFloat = meta.WriteFloat

-- Packed read/write for a positive (index) integer. Note: assumes it never goes above 4 million
function meta:WriteIndex( value )
	if value>4194303 then
		error("Can't write a value over 4194303 (was "..tostring(value)..")!")
	end

	if value<=127 then
		f_WriteByte(self,value)
	elseif value<=16383 then
		f_WriteByte(self,bit_bor(bit_band(value,127),128))
		f_WriteByte(self,bit_rshift(value,7))
	else
		f_WriteByte(self,bit_bor(bit_band(value,127),128))
		f_WriteByte(self,bit_bor(bit_band(bit_rshift(value,7),127),128))
		f_WriteByte(self,bit_rshift(value,14))
	end
end
function meta:ReadIndex()
	local value = f_ReadByte(self)
	if bit_band(value,128)~=0 then
		local valueb = f_ReadByte(self)
		value = bit_bor(bit_band(value,127),bit_lshift(bit_band(valueb,127),7))
		if bit_band(valueb,128)~=0 then
			valueb = f_ReadByte(self)
			value = bit_bor(value,bit_lshift(bit_band(valueb,127),14))
		end
	end
	return value
end

local f_WriteIndex = meta.WriteIndex
local f_ReadIndex = meta.ReadIndex

-- Write/Read string line.
function meta:ReadStr()
	local s = f_ReadIndex(self)
	if s==0 then return "" end
	return f_Read(self,s)
end
function meta:WriteStr( s )
	f_WriteIndex(self,#s)
	f_Write(self,s)
end

-- Write/Read vector
function meta:ReadVector()
	return Vector(f_ReadFloat(self),f_ReadFloat(self),f_ReadFloat(self))
end
function meta:WriteVector( v )
	f_WriteFloat(self,v.x)
	f_WriteFloat(self,v.y)
	f_WriteFloat(self,v.z)
end

-- Write/Read angles
function meta:ReadAngle()
	return Angle(f_ReadFloat(self),f_ReadFloat(self),f_ReadFloat(self))
end
function meta:WriteAngle( v )
	f_WriteFloat(self,v.pitch)
	f_WriteFloat(self,v.yaw)
	f_WriteFloat(self,v.roll)
end