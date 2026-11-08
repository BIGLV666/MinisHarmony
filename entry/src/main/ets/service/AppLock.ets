import { userAuth } from '@kit.UserAuthenticationKit';

/**
 * Launch-time app lock backed by the system credential UI (PIN / face /
 * fingerprint). It deliberately fails open: if the device has no enrolled
 * credential or the API is unavailable, the app is not locked out forever.
 */
export const APP_LOCK_TRUST_LEVEL: userAuth.AuthTrustLevel =
  userAuth.AuthTrustLevel.ATL3;

export function authenticate(title: string): Promise<boolean> {
  return new Promise<boolean>((resolve: (unlocked: boolean) => void) => {
    let settled: boolean = false;
    const finish = (unlocked: boolean): void => {
      if (!settled) {
        settled = true;
        resolve(unlocked);
      }
    };
    try {
      const param: userAuth.AuthParam = {
        challenge: new Uint8Array([]),
        authType: [
          userAuth.UserAuthType.PIN,
          userAuth.UserAuthType.FACE,
          userAuth.UserAuthType.FINGERPRINT
        ],
        authTrustLevel: APP_LOCK_TRUST_LEVEL
      };
      const widget: userAuth.WidgetParam = { title: title };
      const instance: userAuth.UserAuthInstance =
        userAuth.getUserAuthInstance(param, widget);
      instance.on('result', {
        onResult: (result: userAuth.UserAuthResult) => {
          finish(result.result === userAuth.UserAuthResultCode.SUCCESS);
        }
      });
      instance.start();
    } catch (e) {
      // No credential enrolled or unsupported device: do not block the user.
      finish(true);
    }
  });
}
