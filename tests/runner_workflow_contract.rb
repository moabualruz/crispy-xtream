require 'fileutils'
require 'open3'
require 'tmpdir'
require 'yaml'

ROOT = File.expand_path('..', __dir__)
CI = YAML.load_file(File.join(ROOT, '.github/workflows/ci.yml'))
RELEASE = YAML.load_file(File.join(ROOT, '.github/workflows/release.yml'))

def assert(condition, message)
  raise message unless condition
end

def triggers(workflow)
  workflow['on'] || workflow[true]
end

pull_request = "github.event_name == 'pull_request'"
same_repo = "github.event.pull_request.head.repo.full_name == github.repository"
fork_route = "github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name != github.repository"
jobs = CI.fetch('jobs')
assert(!CI.to_s.include?('always()'), 'CI contains a cancellation-unsafe always() condition')
assert(CI.dig('concurrency', 'cancel-in-progress') != true, 'CI must not cancel in-progress runs')
prepare = jobs.fetch('prepare')
steps = prepare.fetch('steps')
checkout = steps.select { |step| step['uses'].to_s.start_with?('actions/checkout@') }
ruby_setup = steps.find { |step| step['uses'] == 'ruby/setup-ruby@v1' }

assert(triggers(CI).key?('pull_request'), 'pull_request trigger was removed')
assert(triggers(CI).fetch('push').fetch('branches') == ['main'], 'push main trigger changed')
assert(triggers(CI).key?('workflow_dispatch'), 'workflow_dispatch trigger was removed')
assert(prepare['runs-on'].include?('self-hosted') && prepare['runs-on'].include?('linux') && prepare['runs-on'].include?('x64') && prepare['runs-on'].include?('generic'), 'trusted runner is missing required labels')
assert(prepare['runs-on'].include?('pr-{0}-{1}'), 'trusted runner label must include repository and PR')
assert(!prepare['runs-on'].include?('run-{2}') && !prepare['runs-on'].include?('attempt-{3}'), 'trusted runner label must remain stable across runs and attempts')
assert(prepare['group'].nil?, 'runner group must remain unset for repo-level registration')
assert(checkout.length == 1, 'prepare must contain exactly one checkout')
assert(checkout.first['if'].include?(fork_route), 'checkout must run only for forks and non-PR events')
assert(checkout.first.dig('with', 'persist-credentials') == false, 'CI checkout must not persist credentials')
assert(ruby_setup && ruby_setup.dig('with', 'ruby-version') == '3.4', 'CI must provision the documented Ruby version')

route = steps.find { |step| step['name'] == 'Select trusted runner route' }
assert(route, 'trusted runner route selection is missing')
Dir.mktmpdir('runner-route') do |dir|
  output = File.join(dir, 'github-output')
  route_env = {
    'EVENT_NAME' => 'pull_request',
    'HEAD_REPOSITORY' => 'moabualruz/crispy-xtream',
    'BASE_REPOSITORY' => 'moabualruz/crispy-xtream',
    'REPOSITORY_ID' => '1204727171',
    'PR_NUMBER' => '2',
    'GITHUB_OUTPUT' => output
  }
  _stdout, stderr, status = Open3.capture3(route_env, 'bash', '-eu', '-c', route.fetch('run'))
  raise "runner route command failed: #{stderr}" unless status.success?
  assert(File.read(output) == "runs_on=[\"self-hosted\",\"linux\",\"x64\",\"generic\",\"pr-1204727171-2\"]\n", 'trusted runner label must be stable for one repository and PR')
end

trusted_check = steps.find { |step| step['name'] == 'Verify host-prepared PR checkout' }
assert(trusted_check && trusted_check['if'].include?(pull_request) && trusted_check['if'].include?(same_repo), 'trusted checkout verification is missing or misrouted')
assert(trusted_check['run'].include?('test "$(git rev-parse HEAD)" = "$GITHUB_SHA"'), 'trusted checkout must verify exact GITHUB_SHA')

archive = steps.find { |step| step['name'] == 'Create source archive' }
assert(archive && archive['if'].include?(fork_route), 'source archive must be limited to forks and non-PR events')
assert(archive['run'].include?('git archive --format=tar "$GITHUB_SHA"'), 'archive must come from GITHUB_SHA')
upload = steps.find { |step| step['uses'].to_s.start_with?('actions/upload-artifact@') }
artifact_name = 'source-${{ github.run_id }}-${{ github.run_attempt }}'
assert(upload.dig('with', 'name') == artifact_name, 'source artifact must be run and attempt scoped')
assert(upload['if'].include?(fork_route), 'source artifact upload must be limited to forks and non-PR events')

jobs.each do |job_name, job|
  next if job_name == 'prepare'

  job_steps = job.fetch('steps')
  assert(job_steps.none? { |step| step['uses'].to_s.start_with?('actions/checkout@') }, "#{job_name} must not check out source again")
  next if job_name == 'test'

  downloads = job_steps.select { |step| step['uses'].to_s.start_with?('actions/download-artifact@') }
  assert(downloads.length == 1, "#{job_name} must consume the single prepared source artifact")
  assert(downloads.first.dig('with', 'name') == artifact_name, "#{job_name} artifact name must be run and attempt scoped")
end

Dir.mktmpdir('runner-contract-repo') do |repo|
  Dir.mktmpdir('runner-contract-restored') do |restored|
    FileUtils.mkdir_p(File.join(repo, 'tracked'))
    File.write(File.join(repo, 'tracked/source.txt'), 'committed source')
    Open3.capture3('git', 'init', '-q', chdir: repo).then do |out, err, status|
      raise "git init failed: #{out} #{err}" unless status.success?
    end
    Open3.capture3('git', 'config', 'user.name', 'Workflow Contract Test', chdir: repo)
    Open3.capture3('git', 'config', 'user.email', 'workflow-contract@example.invalid', chdir: repo)
    Open3.capture3('git', 'add', 'tracked/source.txt', chdir: repo)
    out, err, status = Open3.capture3('git', 'commit', '-qm', 'fixture', chdir: repo)
    raise "git commit failed: #{out} #{err}" unless status.success?
    sha, err, status = Open3.capture3('git', 'rev-parse', 'HEAD', chdir: repo)
    raise "git rev-parse failed: #{err}" unless status.success?
    sha = sha.strip
    File.write(File.join(repo, 'untracked.txt'), 'must not ship')

    runner_temp = File.join(repo, 'runner-temp')
    FileUtils.mkdir_p(runner_temp)
    _out, err, status = Open3.capture3(
      { 'GITHUB_SHA' => sha, 'RUNNER_TEMP' => runner_temp },
      'bash', '-eu', '-c', archive.fetch('run'), chdir: repo
    )
    raise "workflow archive command failed: #{err}" unless status.success?
    tarball = File.join(runner_temp, 'source.tar.gz')
    _out, err, status = Open3.capture3('tar', '-xzf', tarball, '-C', restored)
    raise "archive extraction failed: #{err}" unless status.success?

    expected, err, status = Open3.capture3('git', 'show', "#{sha}:tracked/source.txt", chdir: repo)
    raise "git show failed: #{err}" unless status.success?
    assert(File.read(File.join(restored, 'tracked/source.txt')) == expected, 'restored source differs from GITHUB_SHA')
    assert(!File.exist?(File.join(restored, '.git')), '.git metadata leaked into source archive')
    assert(!File.exist?(File.join(restored, 'untracked.txt')), 'untracked working tree file leaked into source archive')
    assert(Dir.glob(File.join(restored, '**', '*')).map { |path| path.sub("#{restored}/", '') }.sort == ['tracked', 'tracked/source.txt'], 'archive included files beyond the committed workflow source')
  end
end

release_checkout = RELEASE.fetch('jobs').fetch('release-check').fetch('steps').find do |step|
  step['uses'].to_s.start_with?('actions/checkout@')
end
assert(release_checkout.dig('with', 'persist-credentials') == false, 'release checkout must not persist credentials')

puts 'Runner workflow contract verified'
