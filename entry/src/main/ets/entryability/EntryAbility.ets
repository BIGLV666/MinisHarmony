import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { handleShareWant } from '../service/ShareReceiver';
import { handleDeepLinkWant } from '../service/DeepLinkRouter';
import { SandboxProbe } from '../service/SandboxProbe';
import { SandboxIsh } from '../service/SandboxIsh';

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
   * runs one smoke command, logging the output line by line.
   */
  private runIshIfRequested(want: Want): void {
    const flag = want.parameters !== undefined ? want.parameters['sandboxIsh'] : undefined;
    if (flag !== true && flag !== 'true' && flag !== 1) {
      return;
    }
    SandboxIsh.run(this.context,
      'echo hello-from-ish; uname -a; id; cat /etc/alpine-release').then((report: string) => {
      const lines: string[] = report.split('\n');
      hilog.info(DOMAIN, TAG, 'ISH BEGIN');
      for (let i = 0; i < lines.length; i++) {
        hilog.info(DOMAIN, TAG, 'ISH|%{public}s', lines[i]);
      }
      hilog.info(DOMAIN, TAG, 'ISH END');
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'ISH ERROR %{public}s', error.message);
    });
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
