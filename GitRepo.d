import std.stdio;
import std.process;
import std.file;
import std.string;
import std.regex;


class GitRepo
{
public:
    this(string sRepositoryPath, string sGitPath)
    {
        m_sDir=sRepositoryPath;
        m_sGitPath = sGitPath;
    }

    string GetLatestOriginCommitHash()
    {
        return ExecuteGitCommand("git rev-parse origin/"~GetCurrentBranchName(), true).output;
    }
    string GetLocalCommitHash()
    {
        return ExecuteGitCommand("git rev-parse "~GetCurrentBranchName(), true).output;
    }

    string GetCurrentBranchName()
    {
        return ExecuteGitCommand("git rev-parse --abbrev-ref HEAD", true).output;
    }

    string GetBranchList()
    {
        return ExecuteGitCommand("git branch -a", true).output;
    }


    class Diff
    {
        this(char _type, string _file){type=_type; file=_file;}
        char type;
        string file;
    }
    Diff[] GetDiffs(string sFromCommitHash, string sToCommitHash)
    {
        static auto rgxDiff = regex(r"^([MADRCU])\s+(.+)$");
        Diff[] ret;

        string sResult = ExecuteGitCommand("git diff --name-status "~sFromCommitHash~" "~sToCommitHash).output;
        foreach(string line ; sResult.splitLines)
        {
            auto results = match(line, rgxDiff);
            if(results)
                ret~=new Diff(results.captures[1][0],m_sDir~"/"~results.captures[2]);
            else
                writeln("La ligne ",line," ne correspond pas à la regex de diff");

        }
        return ret;
    }


    bool Fetch()
    {
        return ExecuteGitCommand("git fetch origin -a", true).status==0;
    }

    void Clear()
    {
        ExecuteGitCommand("git reset --hard HEAD", true);
        ExecuteGitCommand("git clean -f", true);
    }

    bool Upgrade()
    {
        return ExecuteGitCommand("git pull origin "~GetCurrentBranchName()).status==0;
    }

    bool CheckoutBranch(string sBranchName)
    {
        return ExecuteGitCommand("git checkout "~sBranchName).status==0;
    }



private:
    string m_sDir;
    string m_sGitPath;

    auto ExecuteGitCommand(string sCmd, bool bSilent=false)
    {
        string sDir = getcwd();
        chdir(m_sDir);

        writeln(">",sCmd);
        string[] command = split(sCmd);
        command[0] = m_sGitPath~command[0];
        auto cmdout = execute(command);

        chdir(sDir);

        if(!bSilent)
            writeln(cmdout.output);

        return cmdout;
    }
}
