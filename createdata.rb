#!/usr/bin/env ruby

# p $*.inspect

size = 1024 # 1MByte

if $*.length > 0
  size = size * $*[0].to_i
end

`mkdir data` if !FileTest.directory?("data")

iflag= `uname`.include?("MINGW") ? "" : "iflag=fullblock"

`dd if=/dev/zero of=/dev/null #{iflag} bs=1024 count=#{size}`
`dd if=/dev/zero of=data/file.dat #{iflag} bs=1024 count=#{size}`

`dd if=/dev/urandom of=/dev/null #{iflag} bs=1024 count=#{size}`
`dd if=/dev/urandom of=data/file.dat #{iflag} bs=1024 count=#{size}`

