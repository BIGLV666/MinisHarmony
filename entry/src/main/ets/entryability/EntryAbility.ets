import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { handleShareWant } from '../service/ShareReceiver';
import { handleDeepLinkWant } from '../service/DeepLinkRouter';
import { SandboxProbe } from '../service/SandboxProbe';
import { SandboxIsh, SandboxOptions, SandboxRunResult } from '../service/SandboxIsh';

const DOMAIN: number = 0x0000;
const TAG: string = 'MinisHarmony';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
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
    SandboxProbe.run(this.context).then((report: string) => {
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
      memory: this.context.filesDir + '/memory'
    };
    const first: string = 'cd /tmp; export MINIS_SMOKE=kept; ' +
      'echo hello-from-ish; uname -a; id; cat /etc/alpine-release';
    const second: string = 'pwd; echo smoke=$MINIS_SMOKE; ' +
      'echo workspace=$(ls /var/minis/workspace | wc -l) entries';
    SandboxIsh.run(this.context, first, 180000, options).then((one: SandboxRunResult) => {
      this.logIsh('ISH1', one.output, one.exitCode, Date.now() - began);
      return SandboxIsh.run(this.context, second, 60000, options);
    }).then((two: SandboxRunResult) => {
      this.logIsh('ISH2', two.output, two.exitCode, Date.now() - began);
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
