# frozen_string_literal: true

require "libexec"

Edownload = 11
Emd5sum = 21
Euntar = 31
Euntgz = 32

REGISTRY = "docker.io"
DOCKER_USER = "initdc"
DOCKER_IMAGE = "xuantie-900"
LATEST = "22.04-v2.6.1-xboot"
ACTION = "--push"

REPO_DIR = Dir.pwd
CACHE_DIR = "#{REPO_DIR}/cache"
DOCKERFILE_DIR = "#{CACHE_DIR}/docker"
DOWNLOAD_DIR = "#{CACHE_DIR}/download"
PREBUILT_DIR = "#{CACHE_DIR}/prebuilt"

# https://distrowatch.com/ubuntu
DOUBLE_TAG = %w[
  20.04-v2.4.0
  20.04-v2.6.1
  22.04-v2.6.1
].freeze

TMPL = %w[
  gcc
  linux
  xboot
].freeze

GCC_TARGET = {
  elf: "gcc-elf-newlib-x86_64",
  glibc: "glibc-x86_64"
}.freeze

registry = ENV["REGISTRY"] || REGISTRY
docker_user = ENV["DOCKER_USER"] || DOCKER_USER
docker_image = ENV["DOCKER_IMAGE"] || DOCKER_IMAGE
imagename = ENV["IMAGENAME"] || "#{docker_user}/#{docker_image}"

re_decompress = ARGV[0] == "--re-decompress"

Libexec.run("mkdir -p #{DOCKERFILE_DIR} #{DOWNLOAD_DIR} #{PREBUILT_DIR}")

DOUBLE_TAG.each do |any|
  double_tag = any

  d_array = any.split("-")
  u_ver = d_array[0]
  xuantie_ver = d_array[1]

  Libexec.run("mkdir -p #{DOWNLOAD_DIR}/#{xuantie_ver} #{PREBUILT_DIR}/#{xuantie_ver}")

  release_info = IO.read("#{xuantie_ver}/RELEASE")
  GCC_TARGET.each do |target_sym, keyword|
    target = target_sym.to_s

    url = nil
    file = nil
    sumfile = nil

    release_info.each_line do |line|
      next unless line.include?(keyword)

      url = line.chomp
      file = url.split("/").last
      sumfile = "#{file}.md5sum"

      md5sum = Libexec.output("cat #{xuantie_ver}/MD5SUM | grep #{keyword}")
      Libexec.run("echo > #{DOWNLOAD_DIR}/#{xuantie_ver}/#{sumfile} '#{md5sum}'")
      break
    end

    Dir.chdir "#{DOWNLOAD_DIR}/#{xuantie_ver}" do
      if File.exist?(file)
        if Libexec.code("md5sum -c #{sumfile}").zero?
          if re_decompress
            prebuilt_any = Libexec.output("ls -1 #{PREBUILT_DIR}/#{xuantie_ver} | grep #{keyword}")

            Libexec.run("rm -rf #{prebuilt_any}") if prebuilt_any

            unless Libexec.code("tar -C #{PREBUILT_DIR}/#{xuantie_ver} -zxvf #{file}").zero?
              Libexec.code("tar -C #{PREBUILT_DIR}/#{xuantie_ver} -zxvf #{file}", Euntar)
            end
          else
            prebuilt_any = Libexec.output("ls -1 #{PREBUILT_DIR}/#{xuantie_ver} | grep #{keyword}")
            if prebuilt_any.empty? && !Libexec.code("tar -C #{PREBUILT_DIR}/#{xuantie_ver} -zxvf #{file}").zero?
              Libexec.code("tar -C #{PREBUILT_DIR}/#{xuantie_ver} -zxvf #{file}", Euntar)
            end
          end
        else
          download_files = []
          Libexec.each_line("ls -1") do |line|
            file = line.chomp
            download_files.push(file) if file.include?(keyword) && !file.include?("sum")
          end
          Libexec.run("rm -rf #{download_files.join(" ")}") unless download_files.empty?

          Libexec.code("wget #{url}", Edownload)
          Libexec.code("md5sum -c #{sumfile}", Emd5sum)

          prebuilt_any = Libexec.output("ls -1 #{PREBUILT_DIR}/#{xuantie_ver} | grep #{keyword}")

          Libexec.run("rm -rf #{prebuilt_any}") if prebuilt_any
          unless Libexec.code("tar -C #{PREBUILT_DIR}/#{xuantie_ver} -zxvf #{file}").zero?
            Libexec.code("tar -C #{PREBUILT_DIR}/#{xuantie_ver} -zxvf #{file}", Euntar)
          end
        end
      elsif Libexec.code("wget #{url}", Edownload)
        Libexec.code("md5sum -c #{sumfile}", Emd5sum)

        prebuilt_any = Libexec.output("ls -1 #{PREBUILT_DIR}/#{xuantie_ver} | grep #{keyword}")

        Libexec.run("rm -rf #{prebuilt_any}") if prebuilt_any
        unless Libexec.code("tar -C #{PREBUILT_DIR}/#{xuantie_ver} -zxvf #{file}").zero?
          Libexec.code("tar -C #{PREBUILT_DIR}/#{xuantie_ver} -zxvf #{file}", Euntar)
        end
      end
    end
  end

  TMPL.each do |tmpl|
    tmpl_file = "Dockerfile.#{tmpl}"
    tmpl_content = IO.read(tmpl_file)

    tag = "#{double_tag}-#{tmpl}"
    dockerfile = "Dockerfile.#{tag}"
    prebuilt_glibc = Libexec.output("ls -1 #{PREBUILT_DIR}/#{xuantie_ver} | grep '#{GCC_TARGET[:glibc]}'")
    prebuilt_elf = Libexec.output("ls -1 #{PREBUILT_DIR}/#{xuantie_ver} | grep '#{GCC_TARGET[:elf]}'")

    next if prebuilt_glibc.empty? || prebuilt_elf.empty?

    content = tmpl_content
              .gsub("{version}", u_ver)
              .gsub("{xuantie_ver}", xuantie_ver)
              .gsub("{glibc}", prebuilt_glibc)
              .gsub("{elf}", prebuilt_elf)

    IO.write("#{DOCKERFILE_DIR}/#{dockerfile}", content)
    build_cmd = "docker buildx build -t #{registry}/#{imagename}:#{tag} -f #{DOCKERFILE_DIR}/#{dockerfile} . #{ACTION}"

    puts build_cmd
    Libexec.run(build_cmd)

    next unless tag == LATEST

    latest_cmd = "docker buildx build -t #{registry}/#{imagename}:latest -f #{DOCKERFILE_DIR}/#{dockerfile} . #{ACTION}"

    puts latest_cmd
    Libexec.run(latest_cmd)
  end
end
