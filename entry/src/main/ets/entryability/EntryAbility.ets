import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { handleShareWant } from '../service/ShareReceiver';
import { handleDeepLinkWant } from '../service/DeepLinkRouter';
import { I18nService } from '../service/I18n';
import { SandboxProbe } from '../service/SandboxProbe';
import { SandboxIsh, SandboxOptions, SandboxRunResult } from '../service/SandboxIsh';

const DOMAIN: number = 0x0000;
const TAG: string = 'MinisHarmony';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    I18nService.init(this.context);
    this.routeWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.routeWant(want);
  }

  private routeWant(want: Want): void {
    this.runProbeIfRequested(want);
    this.runIshIfRequested(want);
    if (handleDeepLinkWant(want)) {
      return;
    }
    handleShareWant(want).catch((error: Error) => {});
  }

  /**
   * `hdc shell aa start ... --ps sandboxProbe true` runs the kernel
   * feasibility probe without tapping the UI. Each report line is logged
   * separately so hilog does not truncate a long message.
   */
  private runProbeIfRequested(want: Want): void {
    const flag = want.parameters !== undefined ? want.parameters['sandboxProbe'] : undefined;
    if (flag !== true && flag !== 'true' && flag !== 1) {
      return;
    }
    const deep = want.parameters !== undefined ? want.parameters['sandboxProbeDeep'] : undefined;
    SandboxProbe.run(this.context, deep === true || deep === 'true' || deep === 1).then((report: string) => {
      const lines: string[] = report.split('\n');
      hilog.info(DOMAIN, TAG, 'PROBE BEGIN');
      for (let i = 0; i < lines.length; i++) {
        hilog.info(DOMAIN, TAG, 'PROBE|%{public}s', lines[i]);
      }
      hilog.info(DOMAIN, TAG, 'PROBE END');
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'PROBE ERROR %{public}s', error.message);
    });
  }

  /**
   * `hdc shell aa start ... --ps sandboxIsh true` boots the iSH sandbox and
   * runs two commands back to back. The second one reads shell state set by
   * the first, which proves the kernel is booted once instead of per call.
   */
  private runIshIfRequested(want: Want): void {
    const flag = want.parameters !== undefined ? want.parameters['sandboxIsh'] : undefined;
    if (flag !== true && flag !== 'true' && flag !== 1) {
      return;
    }
    const began: number = Date.now();
    const options: SandboxOptions = {
      workspace: this.context.filesDir + '/workspace',
      memory: this.context.filesDir + '/memory',
      attachments: this.context.filesDir + '/attachments',
      skills: this.context.filesDir + '/skills'
    };
    const first: string = 'cd /tmp; export MINIS_SMOKE=kept; ' +
      'echo hello-from-ish; uname -a; id; cat /etc/alpine-release';
    const second: string = 'echo pwd=$(pwd); echo smoke=$MINIS_SMOKE; ' +
      'echo workspace=$(ls /var/minis/workspace | wc -l) entries';
    // The preinstalled Python is only useful if its C extensions load, which
    // exercises musl, OpenSSL and SQLite from the offline package set.
    const third: string = 'python3 -c "import ssl, sqlite3, sys; ' +
      'print(\'python\', sys.version.split()[0])"; echo python_exit=$?';
    // Node is a 47 MB V8 binary under Asbestos; a cold start is the most
    // demanding thing the guest runs. npm proves the CA bundle and the
    // node_modules tree survived packing.
    const fourth: string = 'node --version; echo node_exit=$?; ' +
      'npm --version; echo npm_exit=$?';
    // iSH has no slirp: guest sockets are forwarded to the host, so DNS and a
    // raw TCP connect exercise the whole path without depending on a proxy.
    const fifth: string = 'python3 -c "import socket; ' +
      'print(\'dns\', socket.gethostbyname(\'example.com\')); ' +
      's = socket.create_connection((\'1.1.1.1\', 443), 15); ' +
      'print(\'tcp\', s.getpeername()); s.close()"; echo net_exit=$?';
    SandboxIsh.run(this.context, first, 180000, options).then((one: SandboxRunResult) => {
      this.logIsh('ISH1', one.output, one.exitCode, Date.now() - began);
      return SandboxIsh.run(this.context, second, 60000, options);
    }).then((two: SandboxRunResult) => {
      this.logIsh('ISH2', two.output, two.exitCode, Date.now() - began);
      return SandboxIsh.run(this.context, third, 120000, options);
    }).then((three: SandboxRunResult) => {
      this.logIsh('ISH3', three.output, three.exitCode, Date.now() - began);
      return SandboxIsh.run(this.context, fourth, 240000, options);
    }).then((four: SandboxRunResult) => {
      this.logIsh('ISH4', four.output, four.exitCode, Date.now() - began);
      return SandboxIsh.run(this.context, fifth, 120000, options);
    }).then((five: SandboxRunResult) => {
      this.logIsh('ISH5', five.output, five.exitCode, Date.now() - began);
      hilog.info(DOMAIN, TAG, 'ISH END total=%{public}dms',
        Date.now() - began);
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'ISH ERROR %{public}s', error.message);
    });
  }

  private logIsh(tag: string, output: string, exitCode: number, elapsed: number): void {
    const lines: string[] = output.split('\n');
    hilog.info(DOMAIN, TAG, '%{public}s BEGIN exit=%{public}d at=%{public}dms',
      tag, exitCode, elapsed);
    for (let i = 0; i < lines.length; i++) {
      hilog.info(DOMAIN, TAG, '%{public}s|%{public}s', tag, lines[i]);
    }
    hilog.info(DOMAIN, TAG, '%{public}s END', tag);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Content loaded');
      // Boot the sandbox once the first screen is up, so the first shell
      // command does not also pay the kernel start. Warm() is a no-op until
      // the rootfs has been extracted once, so a fresh install is unaffected.
      setTimeout((): void => {
        SandboxIsh.warm(this.context);
      }, 2000);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Window stage destroyed');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }
}
