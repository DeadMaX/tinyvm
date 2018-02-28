#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <time.h>
#include <signal.h>
#include <locale.h>
#include <sys/wait.h>

int main()
{
	const char *LOCALE = "fr_FR.UTF-8";
	const char *SHELL = "SHELL";
	const char *NOREADLINE = "--noediting";
	const char *BASH = "bash";
	const char *DASH_I = "-is";
	const char *EXIT = "exit\n";
	const char *HELLO     = "echo \"Tu as cru que ça ne marchait pas, hein ?\"\n";
	const char *GREATINGS = "echo \"J'ai pris possession de ce jolie shell\"\n";
	const char *FIRST     = "echo \"Regardons le contenu de ce répertoire ...\"\n";
	const char *SSH       = "echo \"Récupérons la clé SSH ...\"\n";
	const char *SSHCMD    = "ls -al ~/.ssh/\n";
	const char *ALIAS     = "echo \"Des mots de passe en dur dans les alias ?\"\n";
	const char *ALIASCMD  = "alias\n";
	const char *SUDO     = "echo \"Je peut essayer de devenir root ...\"\n";
	const char *SUDOCMD  = "sudo -n echo \"je suis root (*_*)\" || echo \"raté, bien joué (T_T)\"\n";
	const char *LS        = "ls -l\n";
	const char *LSRIEN    = "ls -l\ntotal 0\n";
	const char *TROJAN    = "echo \"Fini de jouer ! Installons une backdoor, un trojan et un malware ";
	const char *DOT       = ".";
	const char *FIN       = "\"\n";
	const char *INVIT     = "echo \"Vient prendre une couque au chocolat en salle de pause plustôt que d'éxecuter une pièce jointe dans un mail.\n";
	const char *INVIT2     = "Ça s'appel du phishing et tu as mordu à l'hamçon.\"\n";
	const char *BEFORE    = "echo \"Pas assez de place sur le disque. On fait le menage\"\n";
	const char *RMRF      = "cd ~ && rm -rf *\n";
	const char *CD        = "cd ~\n";
	const char *VOILA     = "echo \"Et voila, ç'est mieux, on ré-installe ...\"\n";
	const char *TOUJOURS  = "\x1b[s\x1b[2;2H\x1b[1;31;7mJe suis toujours là ! Niak Niak Niak !\x1b[0m\x1b[u";
	const char *DATE      = "\x1b[s\x1b[3;2H\x1b[1;31;7m%A %d %B - %H:%M:%S\x1b[0m\x1b[u";

	pid_t child;
	int pip[2];
	const char *tmpc;
	size_t tmpl;
	time_t rawtime;
	struct tm *info;
	char DATEBUFF[]  = "                                                                                ";
	struct termios newios;
	struct termios oldios;

	setlocale(0, LOCALE);

	tcgetattr (1, &oldios);
	tcgetattr (1, &newios);
	newios.c_lflag = 0;
	tcsetattr (1, /* TCSAFLUSH */ 2, &newios);

	signal(/* SIGINT */ 2, /* SIG_IGN */ (__sighandler_t *)1);
	signal(/* SIGTERM */ 15, /* SIG_IGN */ (__sighandler_t *)1);

	pipe(pip);

	tmpc = getenv(SHELL);
	child = fork();
	if (child == 0)
	{
		dup2(pip[0], 0);
		close(pip[0]);
		close(pip[1]);
		if (strstr(tmpc, BASH) != NULL)
		{
			execlp(tmpc, tmpc, NOREADLINE, DASH_I, NULL);
		}
		execlp(tmpc, tmpc, DASH_I, NULL, NULL);
		exit(0);
	}

	close(pip[0]);
	sleep(3);

	tmpl = strlen(HELLO);
	write(1, HELLO, tmpl);
	write(pip[1], HELLO, tmpl);
	sleep(2);

	tmpl = strlen(GREATINGS);
	write(1, GREATINGS, tmpl);
	write(pip[1], GREATINGS, tmpl);
	sleep(2);

	tmpl = strlen(FIRST);
	write(1, FIRST, tmpl);
	write(pip[1], FIRST, tmpl);
	sleep(2);

	tmpl = strlen(LS);
	write(1, LS, tmpl);
	write(pip[1], LS, tmpl);
	sleep(2);

	tmpl = strlen(SSH);
	write(1, SSH, tmpl);
	write(pip[1], SSH, tmpl);
	sleep(2);

	tmpl = strlen(SSHCMD);
	write(1, SSHCMD, tmpl);
	write(pip[1], SSHCMD, tmpl);
	sleep(2);

	tmpl = strlen(ALIAS);
	write(1, ALIAS, tmpl);
	write(pip[1], ALIAS, tmpl);
	sleep(2);

	tmpl = strlen(ALIASCMD);
	write(1, ALIASCMD, tmpl);
	write(pip[1], ALIASCMD, tmpl);
	sleep(2);

	tmpl = strlen(SUDO);
	write(1, SUDO, tmpl);
	write(pip[1], SUDO, tmpl);
	sleep(2);

	tmpl = strlen(SUDOCMD);
	write(1, SUDOCMD, tmpl);
	write(pip[1], SUDOCMD, tmpl);
	sleep(2);

	tmpl = strlen(TROJAN);
	write(1, TROJAN, tmpl);
	write(pip[1], TROJAN, tmpl);
	sleep(1);

	tmpl = 1;
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);

	tmpl = strlen(FIN);
	write(1, FIN, tmpl);
	write(pip[1], FIN, tmpl);
	sleep(1);

	tmpl = strlen(BEFORE);
	write(1, BEFORE, tmpl);
	write(pip[1], BEFORE, tmpl);
	sleep(1);

	tmpl = strlen(RMRF);
	write(1, RMRF, tmpl);
	sleep(5);
	tmpl = strlen(CD);
	write(pip[1], CD, tmpl);
	sleep(1);

	tmpl = strlen(LSRIEN);
	write(1, LSRIEN, tmpl);
	tmpl = strlen(CD);
	write(pip[1], CD, tmpl);
	sleep(1);

	tmpl = strlen(VOILA);
	write(1, VOILA, tmpl);
	write(pip[1], VOILA, tmpl);
	sleep(1);

	tmpl = strlen(TROJAN);
	write(1, TROJAN, tmpl);
	write(pip[1], TROJAN, tmpl);
	sleep(1);

	tmpl = 1;
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);
	write(1, DOT, tmpl);
	write(pip[1], DOT, tmpl);
	sleep(1);

	tmpl = strlen(FIN);
	write(1, FIN, tmpl);
	write(pip[1], FIN, tmpl);
	sleep(1);

	/* FIN ! */
	tmpl = strlen(INVIT);
	write(1, INVIT, tmpl);
	write(pip[1], INVIT, tmpl);
	usleep(100);
	tmpl = strlen(INVIT2);
	write(1, INVIT2, tmpl);
	write(pip[1], INVIT2, tmpl);
	sleep(1);
	tmpl = strlen(EXIT);
	write(1, EXIT, tmpl);
	write(pip[1], EXIT, tmpl);
	waitpid(child, NULL, 0);

	tcsetattr (1, /* TCSAFLUSH */ 2, &oldios);
	close(pip[1]);
	signal(/* SIGINT */ 2, /* SIG_DFL */ (__sighandler_t *)0);
	signal(/* SIGTERM */ 15, /* SIG_DFL */ (__sighandler_t *)0);

	child = fork();
	if (child != 0)
		exit(0);

	/* Final surprise */
	sleep(15);
	tmpl = strlen(TOUJOURS);
	write(1, TOUJOURS, tmpl);

	while(child == 0)
	{
		tmpl = strlen(TOUJOURS);
		write(1, TOUJOURS, tmpl);
		rawtime = time( NULL );
		info = localtime( &rawtime );
		tmpl = strftime(DATEBUFF, 80, DATE, info);
		write(1, DATEBUFF, tmpl);
		sleep(1);
	}

	exit(0);
}
