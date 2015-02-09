require "backports" # gem backports
require "fpm/package"
require "fpm/util"
require "archive/tar/minitar"
require "digest"
require "fileutils"
require "xz"

class FPM::Package::FreeBSD < FPM::Package
  def self.default_abi
    abi_name = %x{uname -s}.chomp
    abi_version = %x{uname -r}.chomp.split(".")[0]
    abi_arch = %x{uname -m}.chomp

    [abi_name, abi_version, abi_arch].join(":")
  end

  option "--abi", "ABI",
         "Sets the FreeBSD abi pkg field to specify binary compatibility.",
         :default => default_abi

  option "--origin", "ABI",
         "Sets the FreeBSD 'origin' pkg field",
         :default => "fpm/<name>"

  def output(output_path)
    output_check(output_path)

    # Build the packaging metadata files.
    files = {}
    self.files.each do |f|
      files[f] = Digest::SHA1.file(File.join(staging_path, f)).hexdigest
    end

    pkg_origin = attributes[:freebsd_origin]
    if pkg_origin == "fpm/<name>"  # fill in default
      pkg_origin = "fpm/#{name}"
    end

    pkgdata = {
      "abi" => attributes[:freebsd_abi],
      "name" => name,
      "version" => version,
      "comment" => description,
      "desc" => description,
      "origin" => pkg_origin,
      "maintainer" => maintainer,
      "www" => url,
      # prefix is required, but it doesn't seem to matter
      "prefix" => "/",
    }

    # Write +COMPACT_MANIFEST, without the "files" section.
    File.open(File.join(staging_path, "+COMPACT_MANIFEST"), "w+") do |file|
      file.write(pkgdata.to_json + "\n")
    end

    # Populate files + checksums, then write +MANIFEST.
    pkgdata["files"] = {}
    files.each do |f, shasum|
      pkgdata["files"]["/" + f] = shasum
    end

    File.open(File.join(staging_path, "+MANIFEST"), "w+") do |file|
      file.write(pkgdata.to_json + "\n")
    end

    # Create the .txz package archive from the files in staging_path.
    XZ::StreamWriter.open(output_path) do |xz|
      tar = Archive::Tar::Minitar::Output.new(xz)

      # The manifests must come first for pkg.
      add_path(tar, "+COMPACT_MANIFEST",
              File.join(staging_path, "+COMPACT_MANIFEST"))
      add_path(tar, "+MANIFEST",
              File.join(staging_path, "+MANIFEST"))

      files.keys.each do |path|
        add_path(tar, "/" + path, File.join(staging_path, path))
      end
    end
  end # def output

  def add_path(tar, tar_path, path)
    stat = File.lstat(path)
    opts = {
      :size => stat.size,
      :mode => stat.mode,
      :mtime => stat.mtime,
    }

    if stat.directory?
      tar.tar.mkdir(tar_path, opts)
    elsif stat.symlink?
      tar.tar.symlink(tar_path, File.readlink(path), opts)
    else
      tar.tar.add_file_simple(tar_path, opts) do |io|
        File.open(path) do |fd|
          chunk = nil
          size = 0
          while chunk = fd.read(16384) do
            size += io.write(chunk)
          end
          if size != stat.size
            raise "Failed to add #{path} to the archive; expected to " +
                  "write #{stat.size} bytes, only wrote #{size}"
          end
        end
      end # tar.tar.add_file_simple
    end
  end # def add_path

  def to_s(format=nil)
    return super("NAME-VERSION.txz") if format.nil?
    return super(format)
  end # def to_s
end # class FPM::Package::FreeBSD
