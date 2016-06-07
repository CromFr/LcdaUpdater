module main;

import std.stdio;
import std.file;
import std.regex;
import std.string;
import std.conv;
import std.process;

import GitRepo;
import INIReader;

string DIR_REPO;
string DIR_OVERRIDE ;
string DIR_MODULE;
string DIR_UNKNOWN;


string GetFileDestination(string sFilePath, ref string sErrors)
{
    static auto rgxFile = regex(`^\"?(.*[/\\])*(.*)(\.([a-zA-Z0-9]+))\"?$`);

    auto results = match(sFilePath, rgxFile);
    if(results)
    {
        //writeln("Path: ", results.captures[1], "\tName: ", results.captures[2], "\tExt: ", results.captures[4],"\nResults=",results);

        string sFileName = results.captures[2];
        string sExtension = results.captures[4];

        if(    sFileName==".gitignore"
            || sFileName==".gitattributes"
            || sFileName=="LcdaDev.sublime-project")
            return "";

        switch(sExtension.toLower())
        {
            case "are","dlg","fac","git","jrl","ncs","nss","ndb","trx","ult","upe","utc","utd","ute","uti","utm","utp","utr","utt","utw","xml","2da":
                return DIR_OVERRIDE~"/"~sFileName~"."~sExtension;

            case "ifo","gff":
                return DIR_MODULE~"/"~sFileName~"."~sExtension;

            case "trn","gic","pfb","dat":
                return "";

            default:
                sErrors~="Destination du fichier '"~sFilePath~"'' inconnue ! Le fichier à été placé dans "~DIR_UNKNOWN~" pour plus de sûreté\n";
                return DIR_UNKNOWN~"/"~sFileName~"."~sExtension;
        }
    }
    else
        sErrors~="Format du fichier inconnu : '"~sFilePath~"'. Le fichier à été placé dans "~DIR_UNKNOWN~" pour plus de sûreté\n";

    return DIR_UNKNOWN;

}

void InitDirs(bool bClear)
{
    foreach(string sPath ; [DIR_OVERRIDE,DIR_UNKNOWN,DIR_MODULE])
    {

        if(exists(sPath) && bClear)
        {
            writeln("Réinitialisation de ",sPath);
            rmdirRecurse(sPath);
        }
        if(!exists(sPath))
            mkdirRecurse(sPath);
    }
}



int main(string[] args)
{
    try
    {
        INIReader ir = new INIReader("LcdaUpdater.ini");
        DIR_REPO = ir.Get("Path", "LcdaDev");
        DIR_OVERRIDE = ir.Get("Path", "Override");
        DIR_MODULE = ir.Get("Path", "Module");
        DIR_UNKNOWN = ir.Get("Path", "Unknown");

        GitRepo gr = new GitRepo(DIR_REPO, ir.Get("Path", "Git"));

        version(Windows) executeShell("chcp 65001");

        writeln("Ce script va permettre de stripper et mettre en production le module afin de procéder à une mise à jour du module."w);
        writeln("ATTENTION : Si les HAK ou le TLK ont été modifiés, il faudra les mettre à jour manuellement !");
        writeln();
        writeln("Appuyez sur [ENTREE] pour continuer...");
        readln();

        gr.Clear();

        if(!gr.Fetch())
        {
            writeln("Le programme n'a pas pu récupérer les informations depuis BitBucket !");
            writeln("Appuyez sur [ENTREE] pour quitter...");
            readln();
            return 1;
        }

        auto branch = "origin/master";
        writeln("Branche à utiliser [",branch,"] : ");
        string sAns = readln();
        if(sAns!="\n"){
            writeln("Selection de la branche : ",branch);
            branch = sAns;
        }

        do
        {
            writeln("Procéder à une mise à jour complète ou intelligente? (c/i)");
            sAns = readln();
        }while(sAns[0]!='c' && sAns[0]!='i');

        string sErrs;
        if(sAns[0]=='c')
            sErrs = CompleteInstall(gr, branch);
        else
            sErrs = IntelligentInstall(gr, branch);

        writeln();
        writeln("Pushing online tag to origin");
        gr.PushDateTag();

        if(sErrs!="")
        {
            writeln();
            writeln();
            writeln("Quelque chose ne s'est pas passé correctement durant l'installation de ces fichiers :");
            writeln(sErrs);
        }

        writeln();
        writeln("Mise à jour terminée, vous pouvez rebooter le serveur");
        writeln("Appuyez sur [ENTREE] pour quitter...");
        readln();
    	return 0;
    }
    catch(Exception e)
    {
        writeln(to!string(e));
        writeln("Appuyez sur [ENTREE] pour quitter...");
        readln();
        return 1;
    }
}


string CompleteInstall(ref GitRepo gr, string branch)
{
    string sErrors;
    if(gr.Upgrade(branch))
    {
        writeln("Appuyez sur [ENTREE] pour commencer l'installation...");
        readln();

        InitDirs(true);

        //List files in dir
        foreach(DirEntry entry; dirEntries(DIR_REPO, SpanMode.shallow))
        {
            if(entry.isFile)
            {
                string sDestination = GetFileDestination(entry.name, sErrors);
                if(sDestination!="")
                {
                    writeln("ADDED   : ",entry.name," --> ",sDestination);
                    copy(entry.name, sDestination);
                }
                else
                    writeln("STRIPPED: ",entry.name);
            }
        }

        std.file.write(DIR_MODULE~"/InstalledCommit.txt", gr.GetLocalCommitHash());
    }
    return sErrors;
}

string IntelligentInstall(ref GitRepo gr, string branch)
{
    if(!exists(DIR_MODULE~"/InstalledCommit.txt"))
    {
        writeln("Le commit installé n'a pas été retrouvé : vous devez procéder à une mise à jour complète");
        return "";
    }

    string sFromCommit = cast(string)(read(DIR_MODULE~"/InstalledCommit.txt"));

    string sErrors;
    if(gr.Upgrade(branch))
    {
        string sToCommit = gr.GetLocalCommitHash();

        auto diffs = gr.GetDiffs(sFromCommit, sToCommit);

        writeln("Appuyez sur [ENTREE] pour commencer l'installation...");
        readln();

        InitDirs(false);

        foreach(diff; diffs)
        {
            string sDestination = GetFileDestination(diff.file, sErrors);
            try{
                if(sDestination!="")
                {
                    switch(diff.type){
                        case 'M'://Modified
                            if(exists(sDestination))
                            {
                                writeln("UPDATED : ",diff.file," --> ",sDestination);
                                copy(diff.file, sDestination);
                            }
                            else
                                sErrors~="'"~sDestination~"' n'existe pas. Le fichier '"~diff.file~"' n'a pas été mis à jour comme prévu\n";
                            break;

                        case 'A'://Added
                            if(!exists(sDestination))
                            {
                                writeln("ADDED   : ",diff.file," --> ",sDestination);
                                copy(diff.file, sDestination);
                            }
                            else
                                sErrors~="'"~sDestination~"' existe déja. Le fichier '"~diff.file~"' n'a pas été ajouté à l'install comme prévu\n";
                            break;
                        case 'D':
                            if(exists(sDestination))
                            {
                                writeln("DELETED : ",sDestination);
                                remove(sDestination);
                            }
                            else
                                sErrors~="'"~sDestination~"' n'existe pas. Le fichier '"~diff.file~"' n'a pas être supprimé de l'install comme prévu\n";
                            break;
                        default:
                            sErrors~="L'action '"~diff.type~"' pour le fichier '"~diff.file~"' n'est pas gérée\n";
                            break;
                    }
                }
                else
                    writeln("STRIPPED: ",diff.file);
            }catch(Exception e){
                sErrors~="EXCEPTION: "~to!string(e)~"\n";
            }
        }
        std.file.write(DIR_MODULE~"/InstalledCommit.txt", sToCommit);
    }

    return sErrors;
}
