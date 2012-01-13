require 'erb'
require 'yaml'

file = []

task :exam do
	static = YAML::load(File.open('_exams/progdil-2011.yml')) 
	sablon = ERB.new(File.read('_templates/exam.md.erb'))
	title = static['title']
	footer = static['footer']
	
	static['q'].each_with_index do |question, index|
		file[index] = File.read('_includes/q/'+question)
	end
	a = File.open('progdil.md', 'w')
	a.write(sablon.result(binding))
	a.close

	%x( markdown2pdf progdil.md )
	%x( rm -rf progdil.md )
end