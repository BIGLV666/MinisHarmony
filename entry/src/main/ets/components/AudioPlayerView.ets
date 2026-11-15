import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { mediaClock } from '../core/MediaTime';
import { t } from '../core/I18n';

/**
 * Inline audio player used by user bubbles. The AVPlayer is created on the
 * first tap so a long transcript with many voice notes does not hold a decoder
 * for every file; once prepared it keeps the duration and position in state
 * and is released with the component.
 */
@Component
export struct AudioPlayerView {
  @Prop path: string = '';
  @StorageProp('accentColor') accent: string = '#2F6BFF';

  @State playing: boolean = false;
  @State prepared: boolean = false;
  @State failed: boolean = false;
  @State currentMs: number = 0;
  @State duration: number = 0;

  private player: media.AVPlayer | undefined = undefined;
  private pendingPlay: boolean = false;
  private completed: boolean = false;
  private released: boolean = false;
  /** Open descriptor for the audio file; AVPlayer needs fdSrc for local files. */
  private fd: number = -1;

  aboutToDisappear(): void {
    this.released = true;
    const player: media.AVPlayer | undefined = this.player;
    this.player = undefined;
    if (player !== undefined) {
      player.release();
    }
    this.closeFd();
  }

  private closeFd(): void {
    const fd: number = this.fd;
    this.fd = -1;
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (e) {
      }
    }
  }

  private ensurePlayer(): void {
    if (this.player !== undefined || this.released) {
      return;
    }
    media.createAVPlayer().then((player: media.AVPlayer) => {
      if (this.released) {
        player.release();
        return;
      }
      // AVPlayer's `url` is documented for network sources; local files must
      // be handed over as a descriptor, otherwise setting url silently does
      // nothing and no state ever changes.
      let fd: number = -1;
      let length: number = 0;
      try {
        fd = fs.openSync(this.path, fs.OpenMode.READ_ONLY).fd;
        length = fs.statSync(this.path).size;
      } catch (e) {
        if (fd >= 0) {
          try {
            fs.closeSync(fd);
          } catch (closeError) {
          }
        }
        this.failed = true;
        player.release();
        return;
      }
      this.fd = fd;
      this.player = player;
      this.bind(player);
      player.fdSrc = { fd: fd, offset: 0, length: length };
    }).catch((error: BusinessError) => {
      this.failed = true;
    });
  }

  private bind(player: media.AVPlayer): void {
    player.on('stateChange', (state: string) => {
      if (state === 'initialized') {
        player.prepare();
      } else if (state === 'prepared') {
        this.prepared = true;
        this.duration = player.duration;
        if (this.pendingPlay) {
          this.pendingPlay = false;
          player.play();
        }
      } else if (state === 'playing') {
        this.playing = true;
        this.completed = false;
      } else if (state === 'paused') {
        this.playing = false;
      } else if (state === 'completed') {
        this.playing = false;
        this.completed = true;
        this.currentMs = this.duration;
      } else if (state === 'error') {
        this.playing = false;
        this.failed = true;
        player.release();
        this.player = undefined;
        this.closeFd();
      }
    });
    player.on('timeUpdate', (time: number) => {
      this.currentMs = time;
    });
    player.on('durationUpdate', (duration: number) => {
      if (duration > 0) {
        this.duration = duration;
      }
    });
    player.on('error', (error: BusinessError) => {
      this.playing = false;
      this.failed = true;
      player.release();
      this.player = undefined;
      this.closeFd();
    });
  }

  private togglePlay(): void {
    if (this.failed) {
      // A second tap retries: most failures here are transient (file still
      // being written, decoder busy), and the old player is already released.
      this.failed = false;
      this.prepared = false;
      this.currentMs = 0;
      this.duration = 0;
      this.pendingPlay = true;
      this.ensurePlayer();
      return;
    }
    if (this.player === undefined) {
      this.pendingPlay = true;
      this.ensurePlayer();
      return;
    }
    if (this.playing) {
      this.player.pause();
      return;
    }
    if (this.completed ||
      (this.duration > 0 && this.currentMs >= this.duration)) {
      this.currentMs = 0;
      this.completed = false;
      this.player.seek(0);
    }
    if (this.prepared) {
      this.player.play();
    } else {
      this.pendingPlay = true;
    }
  }

  private seekTo(value: number): void {
    this.currentMs = value;
    this.completed = false;
    if (this.player !== undefined && this.prepared) {
      this.player.seek(Math.floor(value));
    }
  }

  build() {
    Row({ space: 10 }) {
      Text(this.failed ? '!' : (this.playing ? '⏸' : '▶'))
        .fontSize(15)
        .fontColor($r('app.color.on_accent'))
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.failed ? $r('app.color.danger') : this.accent)
        .borderRadius(17)
        .onClick(() => this.togglePlay())
        .accessibilityText(this.playing ? t('暂停') : t('播放'))
      Column({ space: 4 }) {
        Slider({
          value: this.currentMs,
          min: 0,
          max: this.duration > 0 ? this.duration : 1,
          step: 1
        })
          .width('100%')
          .selectedColor(this.accent)
          .trackColor($r('app.color.border'))
          .blockColor(this.accent)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.currentMs = value;
            if (mode === SliderChangeMode.End) {
              this.seekTo(value);
            }
          })
        Row() {
          Text(this.failed ? t('无法播放') : mediaClock(this.currentMs))
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(this.duration > 0 ? mediaClock(this.duration) : '--:--')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width(240)
    .padding({ left: 10, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(10)
  }
}
