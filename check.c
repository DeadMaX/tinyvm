#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <signal.h>
#include <sys/wait.h>

void run()
{
	const char *SHELL = "SHELL";
	const char *NOREADLINE = "--noediting";
	const char *BASH = "bash";
	const char *DASH_I = "-is";
	const char *EXIT = "exit\n";
	const char *HELLO     = "echo \"Tu as cru que ça ne marchait pas, hein ?\"\n";
	const char *GREATINGS = "echo \"J'ai pris possession de ce jolie shell\"\n";
	const char *FIRST     = "echo \"Regardons le contenu de ce répertoire ...\"\n";
	const char *LS        = "ls -l\n";
	const char *LSRIEN    = "ls -l\ntotal 0\n";
	const char *TROJAN    = "echo \"Installons une backdoor, un trojan et un malware ";
	const char *DOT       = ".";
	const char *FIN       = "\"\n";
	const char *INVIT  = "echo \"Vient prendre un petit pain en salle de pause plustôt que d'éxecuter une pièce jointe dans un mail. Ça s'appel du phishing et tu as mordu à l'hamçon.\"\n";
	const char *BEFORE    = "echo \"Pas assez de place sur le disque. On fait le menage\"\n";
	const char *RMRF      = "cd ~ && rm -rf *\n";
	const char *CD        = "cd ~\n";
	const char *VOILA     = "echo \"Et voila, ç'est mieux, on vérifie puis ré-installe\"\n";
	const char *TOUJOURS  = "Je suis toujours là ! Niak Niak Niak !\n";


//	__sighandler_t *ign = (__sighandler_t *)1;
	pid_t child;
	int pip[2];
	const char *tmpc;
	size_t tmpl;

	struct termios newios;
	struct termios oldios;

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

	tmpl = strlen(VOILA);
	write(1, VOILA, tmpl);
	write(pip[1], VOILA, tmpl);
	sleep(1);

	tmpl = strlen(LSRIEN);
	write(1, LSRIEN, tmpl);
	tmpl = strlen(CD);
	write(pip[1], CD, tmpl);
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
	{
		execlp(tmpc, tmpc, NULL, NULL, NULL);
		exit(0);
	}

	/* Final surprise */
	sleep(15);
	tmpl = strlen(TOUJOURS);
	write(1, TOUJOURS, tmpl);

	exit(0);
}
