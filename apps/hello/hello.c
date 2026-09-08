/*
 * hello — f1c200s SDK 示例程序
 *
 * 编译: 仓库根目录 make app           (交叉编译并装入 rootfs overlay)
 * 或  : make app APP=hello
 * 运行(板上串口): hello
 *
 * 新程序模板: 复制本目录为 apps/<你的程序>/, 改 BIN 名与源文件即可,
 * 顶层 make app 会编译 apps 目录下的每个程序。
 */
#include <stdio.h>
#include <unistd.h>

int main(void)
{
	printf("hello from f1c200s (arm926ej-s)\n");
	for (int i = 0; i < 3; i++) {
		printf("tick %d\n", i + 1);
		sleep(1);
	}
	return 0;
}
