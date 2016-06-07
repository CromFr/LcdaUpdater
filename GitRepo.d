import std.stdio;
import std.process;
import std.file;
import std.string;
import std.regex;


class GitRepo
{
public:
    this(string sRepositoryPath, string sGitCmd)
    {
        m_sDir=sRepositoryPath;
        m_sGitCmd = sGitCmd;
    }

    string GetLatestOriginCommitHash()
    {
        return ExecuteGitCommand("rev-parse origin/"~GetCurrentBranchName(), true).output;
    }
    string GetLocalCommitHash()
    {
        return ExecuteGitCommand("rev-parse "~GetCurrentBranchName(), true).output;
    }

    string GetCurrentBranchName()
    {
        return ExecuteGitCommand("rev-parse --abbrev-ref HEAD", true).output;
    }

    string GetBranchList()
    {
        return ExecuteGitCommand("branch -a", true).output;
    }

    void PushDateTag()
    {
        import std.string: format;
        import std.datetime: Clock;
        immutable datetime = Clock.currTime();
        immutable tag = format("Online-%04d-%02d-%02d-%02dh%02d",
            datetime.year,datetime.month,datetime.day,datetime.hour,datetime.minute);
        ExecuteGitCommand("tag "~tag);
        ExecuteGitCommand("push origin tag "~tag);
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

        string sResult = ExecuteGitCommand("diff --name-status "~sFromCommitHash~" "~sToCommitHash).output;
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
        return ExecuteGitCommand("fetch origin -a", true).status==0;
    }

    void Clear()
    {
        ExecuteGitCommand("reset --hard HEAD", true);
        ExecuteGitCommand("clean -f", true);
    }

    bool Upgrade(string sBranchName)
    {
        return ExecuteGitCommand("checkout "~sBranchName).status==0;
    }



private:
    string m_sGitCmd;
    string m_sDir;
    string m_sGitPath;

    auto ExecuteGitCommand(string sCmd, bool bSilent=false)
    {
        string sDir = getcwd();
        chdir(m_sDir);

        writeln(">",m_sGitCmd," ",sCmd);
        string[] command = split(sCmd);
        command = m_sGitCmd~command;
        auto cmdout = execute(command);

        chdir(sDir);

        if(!bSilent)
            writeln(cmdout.output);

        return cmdout;
    }
}
