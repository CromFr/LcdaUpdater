module main;

import std.stdio;
import std.file;
import std.regex;
import std.string;

import GitRepo;

immutable string DIR_OVERRIDE = "Override/Lcda";
immutable string DIR_UNKNOWN = "Override/Unknown";
immutable string DIR_MODULE = "Modules/Lcda";
immutable string DIR_REPO = "LcdaDev";




string GetFileDestination(string sFilePath)
{
    static auto rgxFile = regex(r"^(.*[/\\])*(.*)(\.([a-zA-Z0-9]+))$");

    auto results = match(sFilePath, rgxFile);
    if(results)
    {
        //writeln("Path: ", results.captures[1], "\tName: ", results.captures[2], "\tExt: ", results.captures[4],"\nResults=",results);

        string sFileName = results.captures[2];
        string sExtension = results.captures[4];
        switch(sExtension.toLower())
        {
            case "are","dlg","fac","git","jrl","ncs","nss","ndb","trx","ult","upe","utc","utd","ute","uti","utm","utp","utr","utt","utw","xml":
                return DIR_OVERRIDE~"/"~sFileName~"."~sExtension;

            case "ifo","gff":
                return DIR_MODULE~"/"~sFileName~"."~sExtension;

            case "trn","gic","pfb","dat":
                return "";

            default:
                writeln("Destination du fichier ",sFilePath," inconnue ! Le fichier à été placé dans ",DIR_UNKNOWN," pour plus de sûreté");
                return DIR_UNKNOWN~"/"~sFileName~"."~sExtension;
        }
    }
    else
        writeln("Format du fichier inconnu : ",sFilePath);

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
    GitRepo gr = new GitRepo(DIR_REPO);

    writeln("Ce script va permettre de stripper et mettre en production le module afin de procéder à une mise à jour du module.");
    writeln("ATTENTION : Si les HAK ou le TLK ont été modifiés, il faudra les mettre à jour manuellement !");
    writeln();
    writeln("Appuyez sur [ENTREE] pour continuer...");
    readln();

    gr.Clear();

    if(!gr.Fetch())
        return 1;

    writeln("La branche utilisée est : ",gr.GetCurrentBranchName());
    writeln("Voulez vous utiliser une autre branche ? (o/n)");
    string sAns = readln();
    if(sAns[0]=='o')
    {
        do
        {
            writeln("Liste des branches :");
            writeln(gr.GetBranchList());
            writeln("Branche à utiliser : ");
            sAns = readln();
        }while(gr.CheckoutBranch(sAns)==false);
    }


    do
    {
        writeln("Procéder à une mise à jour complète ou intelligente? (c/i)");
        sAns = readln();
    }while(sAns[0]!='c' && sAns[0]!='i');

    if(sAns[0]=='c')
        CompleteInstall(gr);
    else
        IntelligentInstall(gr);


	return 0;
}


string CompleteInstall(ref GitRepo gr)
{
    InitDirs(true);

    string sErrors;
    if(gr.Upgrade())
    {
        writeln("Appuyez sur [ENTREE] pour commencer l'installation...");
        readln();

        //List files in dir
        foreach(DirEntry entry; dirEntries(DIR_REPO, SpanMode.shallow))
        {
            if(entry.isFile)
            {
                string sDestination = GetFileDestination(entry.name);
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

string IntelligentInstall(ref GitRepo gr)
{
    if(!exists(DIR_MODULE~"/InstalledCommit.txt"))
    {
        writeln("Le commit installé n'a pas été retrouvé : vous devez procéder à une mise à jour complète");
        return "";
    }

    string sFromCommit = cast(string)(read(DIR_MODULE~"/InstalledCommit.txt"));

    InitDirs(false);

    string sErrors;
    if(gr.Upgrade())
    {
        string sToCommit = gr.GetLocalCommitHash();

        auto diffs = gr.GetDiffs(sFromCommit, sToCommit);

        writeln("Appuyez sur [ENTREE] pour commencer l'installation...");
        readln();
        foreach(diff; diffs)
        {
            string sDestination = GetFileDestination(diff.file);
            if(sDestination!="")
            {
                if(diff.type=='M')
                {//Modified
                    if(exists(sDestination))
                    {
                        writeln("UPDATED : ",diff.file," --> ",sDestination);
                        copy(diff.file, sDestination);
                    }
                    else
                        sErrors~="'"~sDestination~"' n'existe pas. Le fichier '"~diff.file~"' n'a pas été mis à jour comme prévu\n";

                }
                else if(diff.type=='A')
                {//Added
                    if(!exists(sDestination))
                    {
                        writeln("ADDED   : ",diff.file," --> ",sDestination);
                        copy(diff.file, sDestination);
                    }
                    else
                        sErrors~="'"~sDestination~"' existe déja. Le fichier '"~diff.file~"' n'a pas été ajouté à l'install comme prévu\n";
                }
                else if(diff.type=='D')
                {//Deleted
                    if(exists(sDestination))
                    {
                        writeln("DELETED : ",sDestination);
                        remove(sDestination);
                    }
                    else
                        sErrors~="'"~sDestination~"' n'existe pas. Le fichier '"~diff.file~"' n'a pas être supprimé de l'install comme prévu\n";
                }
                else
                    sErrors~="L'action '"~diff.type~"' pour le fichier '"~diff.file~"' n'est pas gérée\n";
            }
            else
                writeln("STRIPPED: ",diff.file);
        }
        std.file.write(DIR_MODULE~"/InstalledCommit.txt", sToCommit);
    }

    return sErrors;
}
