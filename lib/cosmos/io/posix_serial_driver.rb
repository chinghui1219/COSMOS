# encoding: ascii-8bit

# Copyright 2014 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

require 'fcntl'
require 'termios' # Requires ruby-termios gem
require 'timeout' # For Timeout::Error

module Cosmos

  # Serial driver for use on Posix serial ports found on UNIX based systems
  class PosixSerialDriver

    # (see SerialDriver#initialize)
    def initialize(port_name = '/dev/ttyS0',
                   baud_rate = 9600,
                   parity = :NONE,
                   stop_bits = 1,
                   write_timeout = 10.0,
                   read_timeout = nil)

      # Convert Baud Rate into Termios constant
      begin
        baud_rate = Object.const_get("Termios::B#{baud_rate}")
      rescue NameError
        raise(ArgumentError, "Invalid Baud Rate, Not Defined by Termios: #{baud_rate}")
      end

      # Verify Parameters
      raise(ArgumentError, "Invalid parity: #{parity}") if parity and !SerialDriver::VALID_PARITY.include?(parity)
      raise(ArgumentError, "Invalid Stop Bits: #{stop_bits}") unless [1,2].include?(stop_bits)
      @write_timeout = write_timeout
      @read_timeout = read_timeout

      parity = nil if parity == :NONE

      # Open the serial Port
      @handle = Kernel.open(port_name, File::RDWR | File::NONBLOCK)
      flags = @handle.fcntl(Fcntl::F_GETFL, 0)
      @handle.fcntl(Fcntl::F_SETFL, flags & ~File::NONBLOCK)
      @handle.extend Termios

      # Configure the serial Port
      tio = Termios::new_termios()
      iflags = 0
      iflags |= Termios::IGNPAR unless parity
      cflags = 0
      cflags |= Termios::CREAD # Enable receiver
      cflags |= Termios::CS8 # 8-bit bytes
      cflags |= Termios::CLOCAL # Ignore Modem Control Lines
      cflags |= Termios::CSTOPB if stop_bits == 2
      cflags |= Termios::PARENB if parity
      cflags |= Termios::PADODD if parity == :ODD
      tio.iflag = iflags
      tio.oflag = 0
      tio.cflag = cflags
      tio.lflag = 0
      tio.cc[Termios::VTIME] = 0
      tio.cc[Termios::VMIN] = 1
      tio.ispeed = baud_rate
      tio.ospeed = baud_rate
      @handle.tcflush(Termios::TCIOFLUSH)
      @handle.tcsetattr(Termios::TCSANOW, tio)
    end

    # (see SerialDriver#close)
    def close
      if @handle
        # Close the serial Port
        @handle.close
        @handle = nil
      end
    end

    # (see SerialDriver#closed?)
    def closed?
      if @handle
        false
      else
        true
      end
    end

    # (see SerialDriver#write)
    def write(data)
      num_bytes_to_send = data.length
      total_bytes_sent = 0
      bytes_sent = 0
      data_to_send = data

      loop do
        begin
          bytes_sent = @handle.write_nonblock(data_to_send)
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK
          result = IO.fast_select(nil, [@handle], nil, @write_timeout)
          if result
            retry
          else
            raise Timeout::Error, "Write Timeout"
          end
        end
        total_bytes_sent += bytes_sent
        break if total_bytes_sent >= num_bytes_to_send
        data_to_send = data[total_bytes_sent..-1]
      end
    end

    # (see SerialDriver#read)
    def read
      begin
        data = @handle.read_nonblock(65535)
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK
        result = IO.fast_select([@handle], nil, nil, @read_timeout)
        if result
          retry
        else
          raise Timeout::Error, "Read Timeout"
        end
      end

      data
    end

    # (see SerialDriver#read_nonblock)
    def read_nonblock
      data = ''

      begin
        data = @handle.read_nonblock(65535)
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK
        # Do Nothing
      end

      data
    end

  end # class PosixSerialDriver

end # module Cosmos
