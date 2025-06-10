#!/usr/bin/env ruby

# Test script to check if S3 upload dependencies are available

puts "🔍 Checking S3 upload dependencies..."

# Check for required gems
begin
  require 'parallel'
  puts "✅ parallel gem is available"
rescue LoadError
  puts "❌ parallel gem is missing - install with: gem install parallel"
end

begin
  require 'aws-sdk-s3'
  puts "✅ aws-sdk-s3 gem is available"
rescue LoadError
  puts "❌ aws-sdk-s3 gem is missing - install with: gem install aws-sdk-s3"
end

# Check for compression tools
if system("which zip > /dev/null 2>&1")
  puts "✅ zip command is available"
else
  puts "❌ zip command is missing"
end

if system("which 7z > /dev/null 2>&1")
  puts "✅ 7z command is available"
else
  puts "⚠️  7z command is missing (optional - only needed for --7zip option)"
end

puts ""
puts "📋 To install missing gems:"
puts "   gem install aws-sdk-s3 parallel"
