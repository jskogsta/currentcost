On the MAX OSX you would have a couple of options to run this daemon. The ones that I have generally used would be: 

1) *NIX screen command. Great option to run stuff in the background and be able to re-attach to the console. Problem is that you generally have to start the process manually.

2) On the commandline itself, and have the Perl daemon daemonize itself, which is coded into the Perl script itself. 

3) Using the Launchctl within MAC OSX itself to automatically fire the daemon upon system reboot. This is my preferred method, and why I have included the LaunchAgent configuration that I am using here. 

For deatils on how to use the MAC OSX Launchctl service, consult a wide range of online resources. Here is an Apple resource that outlines some of this: https://developer.apple.com/library/mac/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html , but also have a look at http://launchd.info/

Anyways: 

1) Place the org.currentcost.plist into the /Library/LaunchDaemons directory.
2) Enable the daemon with the following command: 

# launchctl load -w /Library/LaunchDaemons/org.currentcost.plist

.. and you can find the daemon now loaded: 

[08:24:08] [/Library/LaunchDaemons]$ launchctl list | grep current
55715	0	org.currentcost
[08:25:00] [/Library/LaunchDaemons]$

.. and you can find the process running: 

[08:25:00] [/Library/LaunchDaemons]$ ps -ef | grep current
  501 55715     1   0  8:23am ??         0:00.61 /opt/local/bin/perl /Users/jskogsta/projects/currentcost/currentcost_daemon.pl
  501 55755 55361   0  8:25am ttys002    0:00.00 grep current
[08:25:28] [/Library/LaunchDaemons]$

You can manipulate of course all of this on the CLI, but there are a few OK utilities out there. One being the LaunchControl app, which you can find here: http://www.soma-zone.com/LaunchControl/