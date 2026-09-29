# frozen_string_literal: true

require "tmpdir"
require "stringio"
load File.expand_path("../bin/new-site", __dir__)

RSpec.describe NewSite do
  let(:options) do
    described_class.parse(
      %w[
        --hostname forum.example.com --port 8081 --smtp-address smtp.example.com --smtp-user u
        --smtp-password p --developer-email me@example.com --plugin https://github.com/discourse/discourse-solved.git
      ],
    )
  end

  it "names the container after the hostname and writes a web_only site behind Caddy" do
    expect(options[:name]).to eq("forum")
    web = described_class.web_yml(options, redis_db: 2)
    expect(web["templates"].join).not_to match(/letsencrypt|postgres|redis/)
    expect(web["expose"]).to eq(["127.0.0.1:8081:80"])
    expect(web["env"]).to include(
      "DISCOURSE_HOSTNAME" => "forum.example.com",
      "DISCOURSE_FORCE_HTTPS" => true,
      "DISCOURSE_DB_HOST" => "data",
      "DISCOURSE_DB_NAME" => "discourse_forum",
      "DISCOURSE_REDIS_DB" => 2,
      "DISCOURSE_SMTP_ADDRESS" => "smtp.example.com",
    )
    expect(web["hooks"]["after_code"].first["exec"]["cmd"]).to eq(
      ["git clone https://github.com/discourse/docker_manager.git", "git clone https://github.com/discourse/discourse-solved.git"],
    )
    expect(described_class.caddy_block(options)).to include("forum.example.com {", "reverse_proxy 127.0.0.1:8081")
  end

  it "plans the data container once, picks the next Redis database, and restores a backup last" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "containers"))
      File.write(File.join(dir, "containers", "other.yml"), { "env" => { "DISCOURSE_REDIS_DB" => 3 } }.to_yaml)
      o = options.merge(docker_dir: dir, caddy_dir: File.join(dir, "caddy"), backup: "/tmp/forum.tar.gz")

      steps = described_class.plan(o)
      writes = steps.select { |s| s[0] == :write }.map { |s| File.basename(s[1]) }
      runs = steps.select { |s| s[0] == :run }.map { |s| s[1] }

      expect(writes).to eq(%w[data.yml forum.yml forum.caddy])
      expect(YAML.safe_load(steps[2][2])["env"]["DISCOURSE_REDIS_DB"]).to eq(4)
      expect(runs.first).to include("bootstrap data")
      expect(runs.last).to include("discourse restore forum.tar.gz")

      File.write(File.join(dir, "containers", "data.yml"), "")
      again = described_class.plan(o).select { |s| s[0] == :write }.map { |s| File.basename(s[1]) }
      expect(again).to eq(%w[forum.yml forum.caddy])
    end
  end

  it "only writes and runs with --apply" do
    Dir.mktmpdir do |dir|
      o = options.merge(docker_dir: dir, caddy_dir: File.join(dir, "caddy"))
      out = StringIO.new
      described_class.execute(described_class.plan(o), apply: false, out: out)
      expect(out.string).to include("Dry run", "reverse_proxy 127.0.0.1:8081")
      expect(Dir[File.join(dir, "containers", "*")]).to be_empty
    end
  end
end
