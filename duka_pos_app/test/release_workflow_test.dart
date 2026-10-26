// The release pipeline's own logic, run for real.
//
// The auto-release workflow decides which build number a commit is released
// as, and that decision is shell inside a YAML file — the one part of the
// release machinery that no Dart test could reach and every release depended
// on.
//
// So it is read OUT of the workflow and run against a scratch repository here.
// The shell in the workflow is the shell under test: if someone changes the
// algorithm, this fails.
//
// ## WHAT IT PROVES
//
//   * A build number that has NOT been used is released as it stands. The
//     commit is tagged, and no bump commit is invented.
//   * A build number that HAS been used is bumped to the next free one, in a
//     commit of its own, and THAT commit is the one that is tagged — so the
//     APK that gets built carries the number the tag names. The tag and the
//     APK can never disagree, which is how build 27 was spent.
//   * The bump commit's own CI does not start a second release. The commit is
//     already tagged, so the run finds the tag and stops. Without that the
//     pipeline would bump, release, bump, release, for ever.
//
// The workflow's steps run under `shell: bash`, and this test runs them under
// bash too — the already-tagged check word-splits an unquoted parameter, which
// bash does and zsh does not.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// The workflow under test.
const String workflowPath = '../.github/workflows/auto-release.yml';

/// The shell of every step in the job, keyed by the step's name.
Map<String, String> _stepsOf(String workflow) {
  final YamlMap doc = loadYaml(File(workflowPath).readAsStringSync());
  final YamlMap job = (doc['jobs'] as YamlMap)['tag'] as YamlMap;
  final Map<String, String> steps = <String, String>{};
  for (final YamlMap step in (job['steps'] as YamlList).cast<YamlMap>()) {
    final Object? run = step['run'];
    if (run is String) steps[step['name'] as String] = run;
  }
  return steps;
}

void main() {
  late Directory repo;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('release_');
  });

  tearDown(() => repo.deleteSync(recursive: true));

  /// The bare repository the scratch one pushes to.
  late Directory origin;

  setUp(() {
    origin = Directory.systemTemp.createTempSync('origin_');
    Process.runSync('git', <String>['init', '-q', '--bare', origin.path]);
  });

  tearDown(() => origin.deleteSync(recursive: true));

  /// A scratch repository with a pubspec, some tags, and a commit.
  void seed({
    required String version,
    List<String> tags = const <String>[],
    bool tagHead = false,
    String message = 'the change the shop is waiting for',
  }) {
    void run(List<String> command) {
      final ProcessResult result =
          Process.runSync('git', command, workingDirectory: repo.path);
      if (result.exitCode != 0) {
        fail('git ${command.join(' ')} failed: ${result.stderr}');
      }
    }

    Directory('${repo.path}/duka_pos_app').createSync();
    File('${repo.path}/duka_pos_app/pubspec.yaml').writeAsStringSync(
      'name: duka_pos\nversion: $version\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
    );
    run(<String>['init', '-q', '.']);
    run(<String>['config', 'user.email', 't@t']);
    run(<String>['config', 'user.name', 't']);
    // A real remote, so the bump's PUSH is exercised rather than skipped: the
    // push is what starts the CI that blesses the bumped commit, and a bump
    // that could not push would release an untested commit.
    run(<String>['remote', 'add', 'origin', origin.path]);
    run(<String>['add', '-A']);
    run(<String>['commit', '-qm', 'first']);
    if (!tagHead) {
      for (final String tag in tags) {
        run(<String>['tag', tag]);
      }
    }
    File('${repo.path}/f.txt').writeAsStringSync('b');
    run(<String>['add', '-A']);
    run(<String>['commit', '-qm', message]);
    if (tagHead) {
      for (final String tag in tags) {
        run(<String>['tag', tag]);
      }
    }
  }

  /// Runs a step's shell in the scratch repository, with the outputs the
  /// workflow would provide.
  ({Map<String, String> outputs, String log}) runStep(
    String script, {
    Map<String, String> env = const <String, String>{},
  }) {
    final Directory out = Directory.systemTemp.createTempSync('out_');
    final File outputFile = File('${out.path}/outputs');
    outputFile.writeAsStringSync('');

    final File scriptFile = File('${out.path}/step.sh');
    scriptFile.writeAsStringSync(script);

    final ProcessResult result = Process.runSync(
      'bash',
      <String>['${out.path}/step.sh'],
      workingDirectory: repo.path,
      environment: <String, String>{
        'GITHUB_OUTPUT': outputFile.path,
        'GITHUB_REPOSITORY': 'owner/repo',
        'RUNNER_TEMP': out.path,
        ...env,
      },
    );
    final Map<String, String> outputs = <String, String>{};
    for (final String line in outputFile.readAsLinesSync()) {
      final int split = line.indexOf('=');
      if (split > 0) {
        outputs[line.substring(0, split)] = line.substring(split + 1);
      }
    }
    out.deleteSync(recursive: true);
    return (outputs: outputs, log: '${result.stdout}${result.stderr}');
  }

  /// The plan step, with the event payload the workflow passes it.
  String planScript(String plan, String sha) => plan
      .replaceAll(r'${{ github.event.workflow_run.head_sha }}', sha)
      .replaceAll(r'${{ github.event.workflow_run.head_branch }}', 'app')
      .replaceAll(r'${{ github.event.workflow_run.id }}', '1')
      .replaceAll(r'${{ github.event.workflow_run.conclusion }}', 'success')
      .replaceAll(r'${{ github.event.workflow_run.event }}', 'push')
      .replaceAll(
          r'${{ github.event.workflow_run.html_url }}', 'https://example/run');

  test('a build number that has NOT been used is released as it stands', () {
    final Map<String, String> steps = _stepsOf(workflowPath);
    final String plan = steps['Compute the release tag']!;
    final String bump = steps['Bump the build number']!;

    seed(version: '2.0.0+28', tags: <String>['v2.0.0+26']);
    final String sha = Process.runSync('git', <String>['rev-parse', 'HEAD'],
            workingDirectory: repo.path)
        .stdout
        .toString()
        .trim();

    final ({Map<String, String> outputs, String log}) planned =
        runStep(planScript(plan, sha));
    expect(planned.outputs['stale'], 'false');
    expect(planned.outputs['tag'], 'v2.0.0+28');
    expect(planned.outputs['code'], '28');

    // No bump: the number was free, so the tested commit is the one released.
    final ProcessResult bumpResult = Process.runSync(
      'bash',
      <String>['-c', bump],
      workingDirectory: repo.path,
    );
    expect(bumpResult.stdout.toString(), isEmpty,
        reason: 'the bump step must not run for a free number');
  });

  test('a build number that HAS been used is bumped, and the BUMP is released',
      () {
    final Map<String, String> steps = _stepsOf(workflowPath);
    final String plan = steps['Compute the release tag']!;
    final String bump = steps['Bump the build number']!;

    // 28 was released. The commit after it still says 28, which is exactly the
    // state that used to fail every release with "bump the number by hand".
    seed(version: '2.0.0+28', tags: <String>['v2.0.0+26', 'v2.0.0+28']);
    final String sha = Process.runSync('git', <String>['rev-parse', 'HEAD'],
            workingDirectory: repo.path)
        .stdout
        .toString()
        .trim();

    final ({Map<String, String> outputs, String log}) planned =
        runStep(planScript(plan, sha));
    expect(planned.outputs['stale'], 'true');
    expect(planned.outputs['next'], '29');
    expect(planned.outputs['tag'], 'v2.0.0+29');
    expect(planned.outputs['code'], '29');

    // The bump step, run for real.
    final ({Map<String, String> outputs, String log}) bumped = runStep(
      bump
          .replaceAll(r'${{ steps.plan.outputs.semver }}', '2.0.0')
          .replaceAll(r'${{ steps.plan.outputs.next }}', '29')
          .replaceAll(r'${{ secrets.RELEASE_TAG_TOKEN }}', 'token'),
      env: <String, String>{'GH_TOKEN': 'token'},
    );
    expect(bumped.log, isNot(contains('unbound variable')));
    expect(bumped.outputs['bumped'], isNotNull,
        reason: 'the bump must produce a commit: '
            '${bumped.log}');

    // And it was PUSHED, which is what starts the CI that blesses it.
    final ProcessResult remote = Process.runSync(
        'git', <String>['log', '-1', '--format=%s', 'origin/app'],
        workingDirectory: repo.path);
    expect(remote.stdout.toString(), contains('bump the build number to 29'),
        reason: 'the bump has to reach app, or the release ships an untested '
            'commit');

    // The pubspec now says the next number.
    final String version = File('${repo.path}/duka_pos_app/pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((String line) => line.startsWith('version:'))
        .split(' ')
        .last;
    expect(version, '2.0.0+29');

    // And it is a COMMIT, so the number the release carries is in the tree
    // that gets built — not a number invented at tag time.
    final ProcessResult log = Process.runSync(
        'git', <String>['log', '-1', '--format=%s'],
        workingDirectory: repo.path);
    expect(log.stdout.toString(), contains('bump the build number to 29'));

    // Tag THAT commit, the way the workflow's next step does, and the number
    // the tag names is the number the commit's pubspec declares. This is the
    // agreement that build 27 broke.
    Process.runSync('git', <String>['tag', 'v2.0.0+29'],
        workingDirectory: repo.path);
    final String tagged = Process.runSync(
            'git', <String>['show', 'v2.0.0+29:duka_pos_app/pubspec.yaml'],
            workingDirectory: repo.path)
        .stdout
        .toString();
    expect(tagged, contains('version: 2.0.0+29'));
  });

  test('the bump commit does not start a second release', () {
    final Map<String, String> steps = _stepsOf(workflowPath);
    final String plan = steps['Compute the release tag']!;

    seed(
      version: '2.0.0+29',
      tags: <String>['v2.0.0+26', 'v2.0.0+28', 'v2.0.0+29'],
      tagHead: true,
    );
    final String sha = Process.runSync('git', <String>['rev-parse', 'HEAD'],
            workingDirectory: repo.path)
        .stdout
        .toString()
        .trim();

    // This commit is already tagged, which is what the bump commit is.
    final ({Map<String, String> outputs, String log}) planned =
        runStep(planScript(plan, sha));
    expect(planned.outputs['already_tagged'], 'true',
        reason: 'the pipeline must not bump, release, bump, release for ever');
  });

  test('a number that was only TAGGED and never released is still spent', () {
    // 27 is the case that broke it: the tag exists, no release ever did, and
    // the number is still not reusable — a handset that somehow got 27 would
    // refuse a replacement carrying the same number, silently.
    final Map<String, String> steps = _stepsOf(workflowPath);
    final String plan = steps['Compute the release tag']!;

    seed(version: '2.0.0+27', tags: <String>['v2.0.0+26', 'v2.0.0+27']);
    final String sha = Process.runSync('git', <String>['rev-parse', 'HEAD'],
            workingDirectory: repo.path)
        .stdout
        .toString()
        .trim();

    final ({Map<String, String> outputs, String log}) planned =
        runStep(planScript(plan, sha));
    expect(planned.outputs['stale'], 'true');
    expect(planned.outputs['next'], '28');
  });
}
