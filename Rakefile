task :default => :build

MOD_ID   = "MyNPCBuddy"
MOD_TYPE = "client"
VERSIONS = {
  "42" => "17",
}

VERSIONS.each do |ver, jdk_ver|
  desc "build for #{ver}"
  task "build:#{ver}" do
    build_dir = "#{ver}/media/java/#{MOD_TYPE}"
    Dir.chdir(build_dir) do
      sh "gradle build -PZVersion=#{ver}"
    end
  end
end

desc "build all"
task :build => VERSIONS.keys.map { |ver| "build:#{ver}" }
