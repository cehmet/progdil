require 'pathname'
require 'pythonconfig'
require 'yaml'

CONFIG = Config.fetch('presentation', {})
#sunum dizini
PRESENTATION_DIR = CONFIG.fetch('directory', 'p')
#config dosyasından öntanımlı ayarları al
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')
#resim dosyasının maximum byutlarını belirle
IMAGE_GEOMETRY = [ 733, 550 ]
DEPEND_KEYS = %w(source css js)
DEPEND_ALWAYS = %w(media)
#yapılması istenen görevler ve tanımları
TASKS = {
    :index => 'sunumları indeksle',
    :build => 'sunumları oluştur',
    :clean => 'sunumları temizle',
    :view => 'sunumları görüntüle',
    :run => 'sunumları sun',
    :optim => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

presentation = {}
tag = {}

class File
#yeni yol oluştur ve çalışma dizinine ekle
  @@absolute_path_here = Pathname.new(Pathname.pwd)
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path)
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end

def png_comment(file, string)
#eklenen kitaplık png dosyalarını okur
  require 'chunky_png'
#png dosyaları için bir eklenti
  require 'oily_png'

  image = ChunkyPNG::Image.from_file(file)
  image.metadata['Comment'] = 'raked'
  image.save(file)
end

def png_optim(file, threshold=40000)
  return if File.new(file).size < threshold
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  png_comment(file, 'raked')
end
#jpg dosyalarını iyileştir.
def jpg_optim(file)
#jpg dosyalarını iyileştir
  sh "jpegoptim -q -m80 #{file}"
#iyileştirdiğini yorumla
  sh "mogrify -comment 'raked' #{file}"
end
#jpg ve png dosyalarını iyileştir.
def optim
#alt dizinlerde ki jpg ve png dosyalarını listeler
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]

  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end
#kalan dosyaların en ve boylarını bul
  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    size, i = [w, h].each_with_index.max
    if size > IMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end
#her bir png dosyasını iyileştir
  pngs.each { |f| png_optim(f) }
#her bir jpg dosyasını iyileştir
  jpgs.each { |f| jpg_optim(f) }

  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE)

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir)
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']
    if ! landslide
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"
      exit 1
    end
#landslide bölümü mevcut mu?
    if landslide['destination']
#yapılan ayarların hatalarını belirt
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"
      exit 1
    end
#index.md dosyası mevcut mu?
    if File.exists?('index.md')
#dosya adı olan index'i base'e ata
      base = 'index'
#genel sunum dosyası olduğunu true ile belirle
      ispublic = true
#presentation.md dosyası mevcut mu?
    elsif File.exists?('presentation.md')
#dosya adı olan presentation'u base'e ata
      base = 'presentation'
#genel sunum dosyası olmadığını false ile belirle
      ispublic = false
    else
#.md uzantılı dosyaların olup olmadığını kontrol et yoksa hatayı bas
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"
#1 ile çık
      exit 1
    end

    basename = base + '.html'
    thumbnail = File.to_herepath(base + '.png')
    target = File.to_herepath(basename)
# Var olan dosyaları listele
    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end
 #kullanılmayan ara dosyaları temizle
    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)
    deps.delete(thumbnail)

    tags = []
#sunu dizininin bilgilerinin listele
   presentation[dir] = {
      :basename => basename, # üreteceğimiz sunum dosyasının baz adı
      :conffile => conffile, # landslide konfigürasyonu (mutlak dosya yolu)
      :deps => deps, # sunum bağımlılıkları
      :directory => dir, # sunum dizini (tepe dizine göreli)
      :name => name, # sunum ismi
      :public => ispublic, # sunum dışarı açık mı
      :tags => tags, # sunum etiketleri
      :target => target, # üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, # sunum için küçük resim
    }
  end
end
#sözlük veri yapısında yani hash de ki değerlerin tags değerlerinin değerine #göre boş liste ata
presentation.each do |k, v|
  v[:tags].each do |t|
    tag[t] ||= []
#bu tags lere atama yap
    tag[t] << k
  end
end
#tasktab'a yeni görevler ekledi
tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]

presentation.each do |presentation, data|
  ns = namespace presentation do
    file data[:target] => data[:deps] do |t|
      chdir presentation do
#landslide programın çalıştır
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
#presentation.html dosyasını ayar dosyalarında belirtildiği yere taşı
          mv 'presentation.html', data[:basename]
        end
      end
    end
#
    file data[:thumbnail] => data[:target] do
      next unless data[:public]
#sunum dosyasının görüntüsünü al
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
#tekrar dosyayı boyutlandırdı
      sh "mogrify -resize 240 #{data[:thumbnail]}"
#iyileştirme yap
      png_optim(data[:thumbnail])
    end
#optim görevininin yapacağı işleri belirle
    task :optim do
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail]

    task :build => [:optim, data[:target], :index]
#görüntüle görevini tanımla
    task :view do
      if File.exists?(data[:target])
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
#sunum dosyası yoksa hata bas
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"
      end
    end
#çalıştır görevinin yapacağı işleri belirle
#çalıştır build ve wiev görevlerine bağlıdır 
    task :run => [:build, :view]
#temizle görevini tanımla ve yapacağı işleri belirle
    task :clean do
      rm_f data[:target]
      rm_f data[:thumbnail]
    end
#ön tanımlı görevin build görevine bağlı olduğunu belirle
    task :default => :build
  end

  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end
#p isminde bir çalışma uzayı oluştur
namespace :p do
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end
#build yani inşa et görevini oluştur
  task :build do
    index = YAML.load_file(INDEX_FILE) || {}
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end

  desc "sunum menüsü"
#menü görevini oluştur.
  task :menu do
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1"
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu
end

desc "sunum menüsü"
task :p => ["p:menu"]
task :presentation => :p
