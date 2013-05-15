# -*- coding: utf-8 -*-
require 'rubygems'

require 'azure'
require 'benchmark'
require 'digest/md5'
require 'base64'
require 'parallel'
require "stringio"

Azure.configure do |config|
  config.storage_account_name = "<ACCONT NAME>"
  config.storage_access_key   = "<ACCESS KEY>"
end

BLOB_CONTAINER_NAME = "test-container"
BLOB_NAME = "data/file.dat"
BLOB_BLOCK_SIZE = 1024 * 1024 * 4
BLOB_TIMEOUT = 30 * 4
MD5_ERROR = "md5 mismatch"
MAX_TRIES = 4


def is_windows?
  /mswin|mingw/ =~ RbConfig::CONFIG['host_os']
end

def get_blob_service(blob_container_name)
  azure_blob_service = Azure::BlobService.new
  container = nil
  begin
    container = azure_blob_service.get_container_properties(blob_container_name)
  rescue Azure::Core::Http::HTTPError => e
    container = azure_blob_service.create_container(blob_container_name)
  end
  return azure_blob_service, container
end

def block_upload(azure_blob_service, container_name, blob_name, block_id, chunk)
  tries = 0
  begin
    source_md5 = Base64.strict_encode64(Digest::MD5.digest(chunk))
    tries += 1
    server_md5 = azure_blob_service.create_blob_block(container_name, blob_name, block_id, chunk,
                                                      ":timeout"=>BLOB_TIMEOUT)
    raise RuntimeError, MD5_ERROR if source_md5 != source_md5

  rescue RuntimeError
    puts "#{$!.class}:#{$!.message}"
    if (tries < MAX_TRIES && $!.message == MD5_ERROR)
      sleep(2**tries)
      retry
    else
      raise
    end
  end
end

def file_chunker(file_name, chunk_size, useDup)
  chunker = Enumerator.new do |y|
    File.open(file_name, "rb") { |source|
      id = 1
      content = "x" * chunk_size
      while source.read(chunk_size, content)
        y <<  [id, content.dup] if useDup
        y <<  [id, content]     if !useDup
        id = id + 1
      end
    }
  end
end

def simple_upload(azure_blob_service, container, file_name, blob_name)
  block_list = []
  block_id_prefix = Time.now.strftime("BID_%m%d%H%M%S_")

  file_chunker(file_name, BLOB_BLOCK_SIZE, false).each { | id, chunk |
    block_id = "%s_%010d" % [block_id_prefix, id]
    block_upload(azure_blob_service, container.name, blob_name, block_id, chunk)
    block_list.push([block_id])
  }

  # TODO retry
  result = azure_blob_service.commit_blob_blocks(container.name, blob_name, block_list, ":timeout"=>BLOB_TIMEOUT)
end

def parallel_upload(azure_blob_service, container, file_name, blob_name, options = {})
  block_list = []
  mutex = Mutex.new
  block_id_prefix = Time.now.strftime("BID_%m%d%H%M%S_")

  Parallel.each(file_chunker(file_name, BLOB_BLOCK_SIZE, true), options) {
    | id, chunk |

    block_id = "%s_%010d" % [block_id_prefix, id]

    mutex.synchronize {
      block_list.push([block_id])
    }
    block_upload(azure_blob_service, container.name, blob_name, block_id, chunk)
  }

  # TODO retry
  result = azure_blob_service.commit_blob_blocks(container.name, blob_name, block_list.sort, ":timeout"=>BLOB_TIMEOUT)
end


Benchmark.bm(35) do |bench|
  [1,2,4,8,16,32,64].each {|i|
    bench.report("parallel(process) put blob: %d" % i){
      begin
        container_name = BLOB_CONTAINER_NAME+Time.now.strftime("-%m%d%H%M%S")
        blob_service, container = get_blob_service(container_name);
        parallel_upload(blob_service, container, BLOB_NAME, BLOB_NAME, :in_processes => i)
      rescue
        puts "#{$!.class}:#{$!.message}"
      end
    }
  } if !is_windows?


  [1,2,4,8,16,32,64].each {|i|
    bench.report("parallel(thread) put blob: %d" % i){
      begin
        container_name = BLOB_CONTAINER_NAME+Time.now.strftime("-%m%d%H%M%S")
        blob_service, container = get_blob_service(container_name);
        parallel_upload(blob_service, container, BLOB_NAME, BLOB_NAME, :in_threads => i)
      rescue
        puts "#{$!.class}:#{$!.message}"
      end
    }
  }

  1.times {
    bench.report("simple block blob upload:"){
      begin
        container_name = BLOB_CONTAINER_NAME+Time.now.strftime("-%m%d%H%M%S")
        blob_service, container = get_blob_service(container_name);
        simple_upload(blob_service, container, BLOB_NAME, BLOB_NAME)
      rescue
        puts "#{$!.class}:#{$!.message}"
      end
    }
  }
end

