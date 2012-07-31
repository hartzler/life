require 'erb'
require 'ostruct'

# not used, but alert user its required :) better way?
require 'rubygems'
require 'haml' 
require 'sass'
require "base64"
# HELPERS: move to file?
def platform_name
  if RUBY_PLATFORM == 'java'
    include Java
    java.lang.System.getProperty("os.name")
  else
    RUBY_PLATFORM
  end
end

# TODO: support mac 32 bit
def platform
  case platform_name()
  when /darwin/i
    system("sysctl hw.cpu64bit_capable > /dev/null 2>&1") ? :mac64 : :mac32
  when /linux/i
    system("sysctl hw.cpu64bit_capable > /dev/null 2>&1") ? :linux64 : :linux32
  else
    raise "Unsupported platform #{RUBY_PLATFORM}!"
  end
end

# Cfg options: (Config is a rake constant? BS)
# constant for easy global access in helper functions
Cfg = OpenStruct.new
Cfg.appname = 'Life'

Cfg.platform = platform()
Cfg.rootdir = File.dirname(__FILE__)
Cfg.builddir = 'build'
Cfg.distdir = "#{Cfg.builddir}/dist"
Cfg.xulversion = "14.0.1"
Cfg.cachedir = "cache/#{Cfg.xulversion}"
Cfg.xulsdkdir = "#{Cfg.cachedir}/xulrunner-sdk"
Cfg.xuluri = {
  :base=>"http://ftp.mozilla.org/pub/mozilla.org/xulrunner/releases/#{Cfg.xulversion}/sdk",
  :mac32 => "xulrunner-#{Cfg.xulversion}.en-US.mac-i386.sdk.tar.bz2",
  :mac64 => "xulrunner-#{Cfg.xulversion}.en-US.mac-x86_64.sdk.tar.bz2",
  :linux32 => "xulrunner-#{Cfg.xulversion}.en-US.linux-i686.sdk.tar.bz2",
  :linux64 => "xulrunner-#{Cfg.xulversion}.en-US.linux-x86_64.sdk.tar.bz2",
}
Cfg.xulrunuri = {
  :base=>"http://ftp.mozilla.org/pub/mozilla.org/xulrunner/releases/#{Cfg.xulversion}/runtimes",
  :win => "xulrunner-#{Cfg.xulversion}.en-US.win32.zip",
  :mac => "xulrunner-#{Cfg.xulversion}.en-US.mac.tar.bz2",
  :linux32 => "xulrunner-#{Cfg.xulversion}.en-US.linux-i686.tar.bz2",
  :linux64 => "xulrunner-#{Cfg.xulversion}.en-US.linux-x86_64.tar.bz2",
}
Cfg.xulsdkfile = File.join(Cfg.cachedir,Cfg.xuluri[Cfg.platform])

task :default => [:package]

task :xul do
  download_cache(Cfg.xuluri[Cfg.platform],"#{Cfg.xuluri[:base]}/#{Cfg.xuluri[Cfg.platform]}","xulrunner-sdk")
end

task :clean do 
  `rm -rf #{Cfg.builddir}/`
end
task :build_emoticon_scss do
  lib_base =File.join(Dir.pwd,"lib")
  scss_base =File.join(Dir.pwd,"src","scss")
  scss = ""
  Dir.glob(File.join(lib_base,"images","emoticon","**","*.*")){|file|
    puts file
    ofile = file.clone
    filetype = ofile.split(".").last
    file.sub!(lib_base,"..")
    name = file.split(/\/|\./)[-4..-2].join("-").downcase
    scss+= "\n.#{name} {\n width:15px;\n height:15px;\n background-image: url(data:image/#{filetype};base64,#{Base64.encode64(File.read(ofile)).split("\n").join});\n} "
  }
  puts scss
  File.open(File.join(scss_base,"emoticons.scss"),"w+"){|f|
    f << scss
  }
end

task :build_font_scss do
  lib_base =File.join(Dir.pwd,"lib")
  scss_base =File.join(Dir.pwd,"src","scss")
  scss = ""
  Dir.glob(File.join(lib_base,"fonts","**","*.ttf")){|file|
    puts file
    file.sub!(lib_base,"..")
    scss+= "\n@font-face {\n font-family: '#{file.split("/").last.split(".")[0].downcase}'; font-weight: normal; font-style: normal;\n src: url('#{file}') format('truetype')\n} "
  }
  puts scss
  File.open(File.join(scss_base,"fonts.scss"),"w+"){|f|
    f << scss
  }
end

task :build do
  `mkdir -p #{Cfg.builddir}`
  `cp -r src/xul #{Cfg.builddir}`
  ["#{Cfg.builddir}/xul/application.ini"].each do |erb|
    open(erb,"w"){|f| f.puts ERB.new(File.read("#{erb}.erb")).result()}
  end
  
  # mkdirs
  ["javascript", "css", "images"].map{|d| File.join(Cfg.builddir,'xul','content',d)}.each {|d| `mkdir -p #{d}`}

  # copy libs
  ['javascript','css', "fonts", "images"].each{|d| `cp -R lib/#{d}/* #{File.join(Cfg.builddir,'xul','content',d)}`}

  # build haml
  puts "Building haml..."
  Dir["src/haml/*.haml"].reject{|f| File.basename(f).match(/^[_.]/)}.each{|haml|
    `haml -r #{File.join(Dir.pwd,'lib',"haml_helper.rb")} #{haml} #{Cfg.builddir}/xul/content/#{File.basename(haml,".haml")}.html`}

  # build coffee
  puts "Building coffee script..."
  Dir["src/coffee/*.coffee"].each do |f|
    puts f
    `./#{Cfg.xulsdkdir}/bin/js -f lib/javascript/coffee-script.js -e "print(CoffeeScript.compile(read('#{f}')));" > #{Cfg.builddir}/xul/content/javascript/#{File.basename(f,'.coffee')}.js`
  end
  
  # build sass
  Dir["src/sass/*.sass"].reject{|f| File.basename(f).match(/^[_.]/)}.each{|sass|
    `sass #{sass} #{Cfg.builddir}/xul/content/css/#{File.basename(sass,".sass")}.css`}
end

task :package => [:xul,:clean,:build] do
  case Cfg.platform
  when :mac32, :mac64
    package_mac
  when :linux32, :linux64
    package_linux
  end
end

task :dist => [:package] do
  `rm -rf #{Cfg.builddir}/dist`
  puts "Checking cache for mac runtime..."
  download_cache(Cfg.xulrunuri[:mac],"#{Cfg.xulrunuri[:base]}/#{Cfg.xulrunuri[:mac]}","mac/XUL.framework")
  puts "Building mac dist..."
  distribute_mac

  puts "Checking cache for windows runtime..."
  download_cache(Cfg.xulrunuri[:win],"#{Cfg.xulrunuri[:base]}/#{Cfg.xulrunuri[:win]}","win/xulrunner","unzip")
  puts "Building windows dist..."
  distribute_windows

  puts "Checking cache for linux64 runtime..."
  download_cache(Cfg.xulrunuri[:linux64],"#{Cfg.xulrunuri[:base]}/#{Cfg.xulrunuri[:linux64]}","linux64/xulrunner")
  puts "Building linux64 dist..."
  distribute_linux64
end

def package_linux
  # TODO
  puts "Linux not supported for packaging yet..."
end

def package_mac
  basedir = "#{Cfg.builddir}/#{Cfg.appname}.app/Contents"
  xulframework = "Frameworks/XUL.framework"
  xulversions = "#{xulframework}/Versions"
  [xulversions,"Resources","MacOS"].each{|dir|`mkdir -p #{basedir}/#{dir}`}
  `ln -s $PWD/#{Cfg.xulsdkdir}/bin #{basedir}/#{xulversions}/#{Cfg.xulversion}`
  `cd #{basedir}/#{xulframework} && ln -s Versions/#{Cfg.xulversion}/XUL XUL`
  `cd #{basedir}/#{xulframework} && ln -s Versions/#{Cfg.xulversion}/libxpcom.dylib libxpcom.dylib`
  `cd #{basedir}/#{xulframework} && ln -s Versions/#{Cfg.xulversion}/xulrunner-bin xulrunner-bin`
  `cp -r #{Cfg.builddir}/xul/* #{basedir}/Resources`
  `cp #{Cfg.xulsdkdir}/bin/xulrunner #{basedir}/MacOS`
  `cp platform/mac/Info.plist #{basedir}`
  `cp platform/mac/life.icns #{basedir}/Resources`
  `chmod -R 755 #{Cfg.builddir}/#{Cfg.appname}.app`
end

def distribute_mac
  dmgdir= "#{Cfg.builddir}/dist/mac"
  `mkdir -p #{dmgdir}`
  `ln -s /Applications #{dmgdir}/Applications`

  basedir = "#{dmgdir}/#{Cfg.appname}.app/Contents"
  xulframework = "#{Cfg.cachedir}/mac/XUL.framework"
  ["Frameworks","Resources","MacOS"].each{|dir|`mkdir -p #{basedir}/#{dir}`}
  `cp -R #{xulframework} #{basedir}/Frameworks`
  `cp #{xulframework}/Versions/#{Cfg.xulversion}/xulrunner #{basedir}/MacOS`
  `cp -r #{Cfg.builddir}/xul/* #{basedir}/Resources`
  `cp platform/mac/Info.plist #{basedir}`
  `cp platform/mac/life.icns #{basedir}/Resources`
  `chmod -R 755 #{basedir}/..`
  `cd #{dmgdir} && tar -cjf life_mac.tar.bz2 Life.app`
end

def distribute_linux64
  appdir="#{Cfg.builddir}/dist/linux64"
  `mkdir -p #{appdir}/Life`
  `cp -r build/xul/ #{appdir}/Life`
  `cp -R #{Cfg.cachedir}/linux64/xulrunner #{appdir}/Life/xulrunner`
  `cp #{appdir}/Life/xulrunner/xulrunner-stub #{appdir}/Life/Life`
  `cd #{appdir} && tar -cjf life_linux64.tar.bz2 Life`
end

def distribute_windows
  windir="#{Cfg.builddir}/dist/win"
  `mkdir -p #{windir}/Life`
  `cp -r build/xul/ #{windir}/Life`
  `cp -R #{Cfg.cachedir}/win/xulrunner #{windir}/Life/xulrunner`
  `cp #{windir}/Life/xulrunner/xulrunner-stub.exe #{windir}/Life/Life.exe`
  `cd #{windir} && zip -r life_win.zip Life`
end

def download_cache(file, url, dir, cmd="tar -xjf")
  unless File.exist?(File.join(Cfg.cachedir,dir))
    unless File.exist?(File.join(Cfg.cachedir,file))
      puts "Downloading #{url} -> #{Cfg.cachedir}/#{file} ..."
      `mkdir -p #{Cfg.cachedir}`
      `curl #{url} > #{Cfg.cachedir}/#{file}`
    end
    puts "Expanding #{Cfg.cachedir}/#{file} ..."
    `mkdir -p #{File.join(Cfg.cachedir,File.dirname(dir))}`
    puts "cd #{File.join(Cfg.cachedir,File.dirname(dir))} && #{cmd} #{file}"
    `cd #{File.join(Cfg.cachedir,File.dirname(dir))} && #{cmd} #{File.join(Cfg.rootdir,Cfg.cachedir,file)}`
  end
end

