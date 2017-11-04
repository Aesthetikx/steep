#!/usr/bin/env ruby

require "pathname"

$LOAD_PATH << Pathname(__dir__) + "../lib"

require "steep"
require "rainbow"
require "optparse"

verbose = false

OptionParser.new do |opts|
  opts.on("-v", "--verbose") do verbose = true end
end.parse!(ARGV)

Expectation = Struct.new(:line, :message)

failed = false

ARGV.each do |arg|
  dir = Pathname(arg)
  puts "🏇 Running smoke test in #{dir}..."

  rb_files = []
  expectations = []

  dir.children.each do |file|
    if file.extname == ".rb"
      buffer = ::Parser::Source::Buffer.new(file.to_s)
      buffer.source = file.read
      parser = ::Parser::CurrentRuby.new

      _, comments, _ = parser.tokenize(buffer)
      comments.each do |comment|
        src = comment.text.gsub(/\A#\s*/, '')

        if src =~ /!expects(@(\+\d+))?/
          offset = $2&.to_i || 1
          message = src.gsub!(/\A!expects(@\+\d+)? +/, '')
          line = comment.location.line

          expectations << Expectation.new(line+offset, message)
        end
      end

      rb_files << file
    end
  end

  stderr = StringIO.new
  stdout = StringIO.new

  builtin = Pathname(__dir__) + "../stdlib"
  begin
    driver = Steep::Drivers::Check.new(source_paths: rb_files,
                                       signature_dirs: [builtin, dir],
                                       stdout: stdout,
                                       stderr: stderr)

    driver.run
  rescue => exn
    puts "ERROR: #{exn.inspect}"
    exn.backtrace.each do |loc|
      puts "  #{loc}"
    end

    failed = true
  end

  if verbose
    stdout.string.each_line do |line|
      puts "stdout> #{line.chomp}"
    end

    stderr.string.each_line do |line|
      puts "stderr> #{line.chomp}"
    end
  end

  lines = stdout.string.each_line.to_a.map(&:chomp)

  expectations.each do |expectation|
    deleted = lines.reject! do |string|
      string =~ /:#{expectation.line}:\d+: #{Regexp.quote expectation.message}\Z/
    end

    unless deleted
      puts Rainbow("  💀 Expected error not found: #{expectation.line}:#{expectation.message}").red
      failed = true
    end
  end

  unless lines.empty?
    lines.each do |line|
      if line =~ /:\d+:\d+:/
        puts Rainbow("  🤦‍♀️ Unexpected error found: #{line}").red
        failed = true
      else
        puts Rainbow("  🤦 Unexpected error found, but ignored: #{line}").yellow
      end
    end
  end
end

if failed
  exit(1)
else
  puts Rainbow("All smoke test pass 😆").blue
end
