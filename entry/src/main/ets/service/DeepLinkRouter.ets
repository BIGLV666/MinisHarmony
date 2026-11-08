import { Want } from '@kit.AbilityKit';
import { DEEP_LINK_SCHEME } from '../core/DeepLink';

export const PENDING_DEEP_LINK_KEY: string = 'pendingDeepLink';

/**
 * Consume a `minis://` Want and hand the raw URI to the UI through AppStorage.
 * Returns true when the Want was a deep link, so the caller does not also
 * treat it as shared content.
 */
export function handleDeepLinkWant(want: Want): boolean {
  // Launcher shortcuts deliver their target as a parameter, not as `uri`.
  let uri: string = want.uri !== undefined ? want.uri : '';
  if (uri.length === 0 && want.parameters !== undefined) {
    const parameter: Object | undefined = want.parameters['minis_deep_link'];
    if (typeof parameter === 'string') {
      uri = parameter as string;
    }
  }
  if (uri.length === 0 || uri.toLowerCase().indexOf(DEEP_LINK_SCHEME) !== 0) {
    return false;
  }
  AppStorage.setOrCreate<string>(PENDING_DEEP_LINK_KEY, uri);
  return true;
}
