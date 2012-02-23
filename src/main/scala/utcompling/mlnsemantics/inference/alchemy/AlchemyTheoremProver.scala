package utcompling.scalalogic.inference.alchemy

import utcompling.mlnsemantics.inference.WeightedExpression
import utcompling.scalalogic.fol.expression._
import utcompling.scalalogic.top.expression.Variable
import scala.collection.mutable.ListBuffer
import utcompling.scalalogic.util.SubprocessCallable
import utcompling.scalalogic.util.FileUtils
import utcompling.scalalogic.util.FileUtils._
import org.apache.commons.logging.LogFactory
import utcompling.scalalogic.top.expression.parse.LogicParser
import utcompling.scalalogic.fol.expression.parse.FolLogicParser
import utcompling.mlnsemantics.inference.HardWeightedExpression
import utcompling.mlnsemantics.inference.SoftWeightedExpression
import scala.io.Source

class AlchemyTheoremProver(
  override val binary: String)
  extends SubprocessCallable(binary) //with ProbabilisticTheoremProver[FolExpression, Double] 
  {

  type WeightedFolEx = WeightedExpression[FolExpression]

  private val LOG = LogFactory.getLog(AlchemyTheoremProver.getClass)

  def prove(
    constants: Map[String, Iterable[String]],
    declarations: List[FolExpression],
    evidence: List[FolExpression],
    assumptions: List[WeightedFolEx],
    goal: FolExpression) = {

    declarations.foreach {
      case FolAtom(Variable(pred), args @ _*) =>
        for (a <- args.map(_.name))
          require(constants.contains(a), "No contants were found for argument '%s' of declared predicate '%s'.".format(a, pred))
      case d => throw new RuntimeException("Only atoms may be declared.  '%s' is not an atom.".format(d))
    }

    val entailedConst = ("entail" -> List("entailed"))
    val entailedDec = FolAtom(Variable("entailment"), Variable("entail"))
    val ResultsRE = """entailment\("entailed"\) (\d*\.\d*)""".r

    val entailedGoal: FolExpression = goal -> FolAtom(Variable("entailment"), Variable("entailed"))

    val mlnFile = makeMlnFile(
      constants + entailedConst,
      declarations :+ entailedDec,
      assumptions :+ HardWeightedExpression(entailedGoal))
    val evidenceFile = makeEvidenceFile(evidence)
    val resultFile = FileUtils.mktemp(suffix = ".res")

    val args = List("-q", "entailment")

    callAlchemy(mlnFile, evidenceFile, resultFile, args) map {
      case ResultsRE(score) => score.toDouble
    }
  }

  private def makeMlnFile(
    constants: Map[String, Iterable[String]],
    declarations: List[FolExpression],
    assumptions: List[WeightedFolEx]) = {

    FileUtils.writeUsing(FileUtils.mktemp(suffix = ".mln")) { f =>
      constants.foreach {
        case (name, tokens) => f.write("%s = {%s}\n".format(name, tokens.map(quote).mkString(",")))
      }
      f.write("\n")

      declarations.foreach {
        case FolAtom(pred, args @ _*) => f.write("%s(%s)\n".format(pred.name, args.map(_.name).mkString(",")))
      }
      f.write("\n")

      assumptions.foreach {
        case SoftWeightedExpression(folEx, weight) => f.write(weight + " " + convert(folEx) + "\n")
        case HardWeightedExpression(folEx) => f.write(convert(folEx) + ".\n")
      }
    }
  }

  private def makeEvidenceFile(evidence: List[FolExpression]) = {
    FileUtils.writeUsing(FileUtils.mktemp(suffix = ".db")) { f =>
      evidence.foreach {
        case e @ FolAtom(pred, args @ _*) => f.write(convert(e) + "\n")
        case e => throw new RuntimeException("Only atoms may be evidence.  '%s' is not an atom.".format(e))
      }
    }
  }

  private def callAlchemy(mln: String, evidence: String, result: String, args: List[String] = List()): Option[String] = {
    val allArgs = "-i" :: mln :: "-e" :: evidence :: "-r" :: result :: args
    val (exitcode, stdout, stderr) = callAllReturns(None, allArgs, LOG.isDebugEnabled)

    val results = Source.fromFile(result).getLines.mkString("\n").trim

    exitcode match {
      case 0 =>
        Some(results)
      case _ =>
        throw new RuntimeException("Failed with exitcode=%s.\n%s\n%s".format(exitcode, stdout, stderr))
    }
  }

  private def convert(input: FolExpression, bound: Set[Variable] = Set()): String =
    input match {
      case FolExistsExpression(variable, term) => "exist " + variable.name + " " + convert(term, bound + variable)
      case FolAllExpression(variable, term) => "forall " + variable.name + " " + convert(term, bound + variable)
      case FolNegatedExpression(term) => "!(" + convert(term, bound) + ")"
      case FolAndExpression(first, second) => "(" + convert(first, bound) + " ^ " + convert(second, bound) + ")"
      case FolOrExpression(first, second) => "(" + convert(first, bound) + " v " + convert(second, bound) + ")"
      case FolIfExpression(first, second) => "(" + convert(first, bound) + " => " + convert(second, bound) + ")"
      case FolIffExpression(first, second) => "(" + convert(first, bound) + " <=> " + convert(second, bound) + ")"
      case FolEqualityExpression(first, second) => "(" + convert(first, bound) + " = " + convert(second, bound) + ")"
      case FolAtom(pred, args @ _*) => pred.name.replace("'", "") + "(" + args.map(v => if (bound(v)) v.name else quote(v.name)).mkString(",") + ")"
      case FolVariableExpression(v) => if (bound(v)) v.name else quote(v.name)
    }

  private def quote(s: String) = '"' + s + '"'

}

object AlchemyTheoremProver {

  def findBinary(binDir: Option[String] = None, envar: Option[String] = Some("ALCHEMYHOME"), verbose: Boolean = false) =
    new AlchemyTheoremProver(FileUtils.findBinary("infer", binDir, envar, verbose))

  def main(args: Array[String]) {
    val parse = new FolLogicParser().parse(_)

    val atp = new AlchemyTheoremProver(pathjoin(System.getenv("HOME"), "bin/alchemy/bin/infer"))

    {
      val constants = Map("ind" -> List("socrates"))
      val declarations = List("man(ind)", "mortal(ind)").map(parse)
      val evidence = List("man(socrates)").map(parse)
      val assumptions = List(HardWeightedExpression(parse("all x.(man(x) -> mortal(x))")))
      val goal = parse("mortal(socrates)")
      println(atp.prove(constants, declarations, evidence, assumptions, goal))
    }
  }

}
