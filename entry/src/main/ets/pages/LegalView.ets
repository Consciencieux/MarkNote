import { SubHeader } from '@kit.ArkUI';

/**
 * 「关于」半模态：隐私说明固定，第三方许可证全文由页面读出来后传进来。
 */
@Component
export struct LegalView {
  @Prop text: string = '';

  build() {
    Scroll() {
      Column({ space: 12 }) {
        SubHeader({ primaryTitle: '隐私说明' })
        Text('文稿在设备本地编辑。应用没有账号、广告、遥测或联网接口，也不上传文稿。文件由系统文件选择器授权，草稿保存在应用私有目录。')
          .fontSize($r('sys.float.ohos_id_text_size_body1'))
          .padding({ left: 16, right: 16 })
        SubHeader({ primaryTitle: '第三方开源许可证' })
        Text(this.text)
          .fontSize($r('sys.float.ohos_id_text_size_body2'))
          .fontFamily('monospace')
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
          .copyOption(CopyOptions.LocalDevice)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
  }
}
