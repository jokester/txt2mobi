#!/usr/bin/env ruby -w
require 'tmpdir'
require 'json'

def usage
  STDERR.puts <<END
  USAGE: ruby txt2book.rb filename.txt
END
end

class GitBookCreater
  def initialize title, root_dir
    @title = title
    @root_dir = root_dir
    @content = [ { filename: "README.md", lines: [], title: "Preface"} ]
  end

  def set_readme lines
    @content[0][:lines] = lines
  end

  def add_part title, lines
    filename = "part-%010d.md" % @content.size
    @content.push({ filename: filename, lines: lines, title: title })
  end

  def create_file filename, &block
    filepath = File.join @root_dir, filename
    File.open(filepath, "w", &block)
    STDERR.puts "created #{filepath}"
  end

  def write
    write_metadata
    write_parts
    write_summary
  end

  def write_metadata
    create_file "book.json" do |f|
      f.write ({ title: @title, language: "zh" }).to_json
    end
  end

  def write_parts
    @content.each do |c|
      create_file c[:filename] do |f|
        md_lines( c[:title], c[:lines] ).each do |md_line|
          f.write "#{md_line}\n\n"
        end
      end
    end
  end

  def md_lines title, lines
    md_lines = []
    if title
      md_lines << "# #{title}"
    end
    md_lines + lines
  end

  def write_summary
    create_file "SUMMARY.md" do |f|
      @content.each do |c|
        f.puts "* [%s](%s)" % [ c[:title], c[:filename] ]
      end
    end
  end
end

class TxtReader
  CHAPTER_HEADER = %r{^(.*?)(第[一二三四五六七八九十百千万]+.*[章节部])(.*)$}
  def initialize filename
    @title = File.basename filename,(File.extname filename)
    lines = read_lines filename
    @chapters = read_chapters lines
  end

  def read_lines filename
    lines = File.readlines filename
    lines.each do |line|
      line.sub!(/^[ \t　]*/, '')
      line.gsub!(/[\r\n]*/, '')
    end
  end

  def read_chapters lines
    chapters = {}
    current_chapter = :readme
    current_lines = []

    lines.each_with_index do |line, line_no|
      is_title = (CHAPTER_HEADER =~ line) && [ $1.length < 5, $2.length < 12 ].all?
      if is_title
        if current_chapter.length > 0
          chapters[current_chapter] = current_lines
          current_lines = []
          current_chapter = line
        end
      else
        current_lines << line
      end

      if (line_no == lines.length - 1)
        chapters[current_chapter] = current_lines
      end
    end
    chapters
  end

  def write
    Dir.mktmpdir do |tmpdir|
      creater = GitBookCreater.new @title, tmpdir
      @chapters.each do |title, lines|
        case title
        when :readme
          creater.set_readme lines
        else
          creater.add_part title, lines
        end
      end

      creater.write
      formats = %w/pdf mobi epub/

      children = formats.map do |format|
        fork do
          system "time", "gitbook", format, tmpdir, "#{@title}.#{format}"
        end
      end

      formats.zip(children) do |(f, pid)|
        STDERR.puts "generating #{f} in process##{pid}"
      end

      p Process.waitall
    end
  end
end

def main
  if ARGV.length == 0
    usage
    exit 1
  end

  reader = TxtReader.new ARGV[0]
  reader.write
end

main
