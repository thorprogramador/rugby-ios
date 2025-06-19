#!/usr/bin/env ruby

# Rugby S3 Upload Script with +latest File Refresh
# This script refreshes the +latest file and optionally uploads binaries to S3

require 'fileutils'
require 'find'
require 'optparse'

class RugbyS3Uploader
  def initialize
    @shared_path = File.expand_path('~/.rugby')
    @bin_path = "#{@shared_path}/bin"
    @latest_binaries_path = "#{@bin_path}/+latest"
    @options = parse_options
  end

  def run
    case @options[:action]
    when :refresh
      refresh_latest_file
    when :upload
      refresh_latest_file if @options[:refresh_first]
      upload_to_s3
    when :show
      show_current_binaries
    end
  end

  private

  def parse_options
    options = {
      action: :refresh,
      refresh_first: true,
      dry_run: false,
      processes: 15,
      compression: :zip
    }

    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"
      opts.separator ""
      opts.separator "Actions:"
      
      opts.on("-r", "--refresh", "Refresh +latest file with all cached binaries (default)") do
        options[:action] = :refresh
      end
      
      opts.on("-u", "--upload", "Upload binaries to S3 (requires S3 configuration)") do
        options[:action] = :upload
      end
      
      opts.on("-s", "--show", "Show current binaries without making changes") do
        options[:action] = :show
      end
      
      opts.separator ""
      opts.separator "Options:"
      
      opts.on("--no-refresh", "Don't refresh +latest file before upload") do
        options[:refresh_first] = false
      end
      
      opts.on("--dry-run", "Show what would be done without making changes") do
        options[:dry_run] = true
      end
      
      opts.on("-p", "--processes N", Integer, "Number of parallel upload processes (default: 10)") do |n|
        options[:processes] = n
      end

      opts.on("--7zip", "Use 7zip compression instead of zip (requires 7z command)") do
        options[:compression] = :sevenzip
      end
      
      opts.on("-h", "--help", "Show this help") do
        puts opts
        exit
      end
    end.parse!

    options
  end

  def refresh_latest_file
    puts "🏈 Rugby: Refreshing +latest file with all cached binaries..."
    
    unless Dir.exist?(@bin_path)
      puts "❌ Error: Rugby bin directory not found at #{@bin_path}"
      puts "   Make sure you have run 'rugby build' or 'rugby cache' at least once."
      exit 1
    end

    # Find all target/config combinations and get the latest binary for each
    puts "🔍 Scanning for cached binaries..."
    all_binaries = []
    
    Find.find(@bin_path) do |path|
      next unless File.directory?(path)
      
      # Check if this is a binary hash directory (should be 3 levels deep from bin/)
      relative_path = path.gsub("#{@bin_path}/", "")
      depth = relative_path.split('/').length
      
      if depth == 3 && File.basename(path) =~ /^[a-f0-9]+$/
        all_binaries << path
      end
    end

    # Group by target/config and keep only the latest binary for each
    latest_binaries = {}
    all_binaries.each do |binary_path|
      target_config = File.dirname(binary_path)
      mtime = File.mtime(binary_path)
      
      if !latest_binaries[target_config] || mtime > latest_binaries[target_config][:mtime]
        latest_binaries[target_config] = { path: binary_path, mtime: mtime }
      end
    end

    binaries = latest_binaries.values.map { |entry| entry[:path] }.sort

    if binaries.empty?
      puts "❌ No cached binaries found in #{@bin_path}"
      puts "   Run 'rugby build' or 'rugby cache' to create some binaries first."
      exit 1
    end

    puts "📦 Found #{binaries.length} latest binaries (one per target/config)"

    unless @options[:dry_run]
      # Backup existing +latest file if it exists
      if File.exist?(@latest_binaries_path)
        backup_file = "#{@latest_binaries_path}.backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
        FileUtils.cp(@latest_binaries_path, backup_file)
        puts "💾 Backed up existing +latest file to: #{File.basename(backup_file)}"
      end

      # Write all binary paths to +latest file
      File.write(@latest_binaries_path, binaries.join("\n") + "\n")
      puts "✅ Successfully refreshed +latest file with #{binaries.length} latest binaries (one per target/config)"
    else
      puts "🧪 DRY RUN: Would write #{binaries.length} binaries to +latest file"
    end

    puts "📄 File location: #{@latest_binaries_path}"
    
    # Show sample of what was written
    puts ""
    puts "📋 Sample of binaries:"
    binaries.first(5).each { |binary| puts "   #{binary}" }
    puts "   ... and #{binaries.length - 5} more" if binaries.length > 5
    
    puts ""
    puts "🚀 Your +latest file is now ready for S3 upload scripts!"
  end

  def show_current_binaries
    puts "🏈 Rugby: Current cached binaries"
    
    if File.exist?(@latest_binaries_path)
      content = File.read(@latest_binaries_path).strip
      if content.empty?
        puts "📄 +latest file exists but is empty"
      else
        binaries = content.split("\n").reject(&:empty?)
        puts "📄 +latest file contains #{binaries.length} binaries:"
        binaries.each { |binary| puts "   #{binary}" }
      end
    else
      puts "❌ No +latest file found at #{@latest_binaries_path}"
    end
    
    # Also show what exists in the filesystem
    puts ""
    refresh_latest_file if @options[:dry_run] = true # Show what would be found
  end

  def upload_to_s3
    puts "🔄 Starting S3 upload process..."
    
    # Check for S3 configuration
    s3_config = {
      endpoint: ENV['S3_ENDPOINT'],
      bucket: ENV['S3_BUCKET'],
      access_key: ENV['S3_ACCESS_KEY'],
      secret_key: ENV['S3_SECRET_KEY']
    }
    
    missing_config = s3_config.select { |k, v| v.nil? || v.empty? }.keys
    unless missing_config.empty?
      puts "❌ Missing S3 configuration. Please set these environment variables:"
      missing_config.each { |key| puts "   #{key.to_s.upcase}" }
      puts ""
      puts "Example:"
      puts "   export S3_ENDPOINT='https://s3.eu-west-2.amazonaws.com'"
      puts "   export S3_BUCKET='your-rugby-cache-bucket'"
      puts "   export S3_ACCESS_KEY='your-access-key'"
      puts "   export S3_SECRET_KEY='your-secret-key'"
      exit 1
    end

    unless File.exist?(@latest_binaries_path)
      puts "❌ No +latest file found. Run with --refresh first."
      exit 1
    end

    # Parse binaries from +latest file (following documentation pattern)
    binaries = File.readlines(@latest_binaries_path, chomp: true).each_with_object({}) do |path, hash|
      remote_path = path.delete_prefix("#{@bin_path}/")
      hash[remote_path] = path
    end

    if binaries.empty?
      puts "❌ No binaries found in +latest file"
      exit 1
    end

    puts "📦 Found #{binaries.length} binaries to upload"
    
    if @options[:dry_run]
      puts "🧪 DRY RUN: Would upload these binaries:"
      binaries.each { |remote_path, local_path| puts "   #{remote_path} <- #{local_path}" }
      return
    end

    # Check if required gems are available
    begin
      require 'parallel'
      require 'aws-sdk-s3'
    rescue LoadError => e
      puts "❌ Missing required gems: #{e.message}"
      puts "   Install with: gem install aws-sdk-s3 parallel"
      exit 1
    end

    puts "🚀 Starting upload to S3..."
    puts "📦 Uploading #{binaries.length} binaries using #{@options[:processes]} parallel processes"
    puts "🗜️  Compression: #{@options[:compression] == :sevenzip ? '7zip' : 'zip'}"
    
    # Initialize S3 client
    credentials = Aws::Credentials.new(s3_config[:access_key], s3_config[:secret_key])
    s3 = Aws::S3::Client.new(
      endpoint: s3_config[:endpoint], 
      credentials: credentials,
      ssl_verify_peer: false
    )
    
    # Test S3 connection
    begin
      s3.head_bucket(bucket: s3_config[:bucket])
      puts "✅ S3 connection successful"
    rescue Aws::S3::Errors::NotFound
      puts "❌ S3 bucket '#{s3_config[:bucket]}' not found"
      exit 1
    rescue => e
      puts "❌ S3 connection failed: #{e.message}"
      exit 1
    end

    # Use Parallel.map to collect results from each process
    results = Parallel.map(binaries, in_processes: @options[:processes]) do |remote_path, local_path|
      begin
        binary_folder_path = File.dirname(local_path)
        binary_name = File.basename(local_path)
        
        # Choose compression method
        if @options[:compression] == :sevenzip
          archive_file = "#{local_path}.7z"
          compress_cmd = "cd '#{binary_folder_path}' && 7z a -mx3 '#{binary_name}.7z' '#{binary_name}' > /dev/null 2>&1"
          content_type = 'application/x-7z-compressed'
          remote_key = "#{remote_path}.7z"
        else
          archive_file = "#{local_path}.zip"
          compress_cmd = "cd '#{binary_folder_path}' && zip -r '#{binary_name}.zip' '#{binary_name}' > /dev/null 2>&1"
          content_type = 'application/zip'
          remote_key = "#{remote_path}.zip"
        end
        
        # Create archive file
        if system(compress_cmd)
          # Upload to S3
          File.open(archive_file, 'rb') do |file|
            s3.put_object(
              bucket: s3_config[:bucket],
              body: file,
              content_type: content_type,
              key: remote_key
            )
          end
          
          # Clean up archive file
          File.delete(archive_file) if File.exist?(archive_file)
          
          puts "✅ Uploaded: #{remote_path}"
          :success
        else
          compression_type = @options[:compression] == :sevenzip ? "7zip" : "zip"
          puts "❌ Failed to #{compression_type}: #{remote_path}"
          :failed
        end
      rescue => e
        puts "❌ Upload failed for #{remote_path}: #{e.message}"
        # Clean up archive file on error
        File.delete(archive_file) if defined?(archive_file) && File.exist?(archive_file)
        :failed
      end
    end
    
    # Count the results
    uploaded_count = results.count(:success)
    failed_count = results.count(:failed)
    
    puts ""
    puts "📊 Upload Summary:"
    puts "   ✅ Successfully uploaded: #{uploaded_count}"
    puts "   ❌ Failed: #{failed_count}" if failed_count > 0
    puts "   📦 Total processed: #{binaries.length}"
  end
end

# Run the script
if __FILE__ == $0
  RugbyS3Uploader.new.run
end
