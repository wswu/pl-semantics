package utcompling.mlnsemantics.rules

import opennlp.scalabha.util.CollectionUtils._
import opennlp.scalabha.util.FileUtils._
import org.apache.commons.logging.LogFactory
import utcompling.mlnsemantics.run.Sts
import scala.Array.canBuildFrom
import utcompling.mlnsemantics.datagen.Tokenize
import utcompling.mlnsemantics.datagen.Lemmatize
import utcompling.scalalogic.discourse.impl.PreparsedBoxerDiscourseInterpreter
import utcompling.scalalogic.discourse.DiscourseInterpreter
import utcompling.scalalogic.discourse.candc.boxer.expression.interpreter.impl._
import utcompling.scalalogic.discourse.candc.boxer.expression.BoxerDrs

class DistributionalRules extends Rules{
  
  private val LOG = LogFactory.getLog(classOf[DistributionalRules])

  
  	def getRules() : List[(BoxerDrs, BoxerDrs, Double, RuleType.Value)] = 
	{
		val returnedRules = Sts.luceneDistPhrases.exactMatchingQuery("\t"+Sts.text + "\t" + Sts.hypothesis + "\n")
		LOG.trace("Distributioanl rules: ");
		returnedRules.foreach(rule => LOG.trace(rule))


		val filterStart = System.nanoTime
		val distRules = returnedRules
			.flatMap { rule =>
				val Array(id, ruleLhs, ruleRhs, score, gs, inWN, sen1, sen2, expLhs, expRhs) = rule.split("\t")
				if (Sts.text != sen1 || Sts.hypothesis != sen2)
					None
				else
				{
					val lhs = ruleLhs //.split(" ").map(_.split("-")(0)).mkString(" ")   //keep the index and the POS. It will be used in reconstructing the logical represetnation of the phrase
					val rhs = ruleRhs //.split(" ").map(_.split("-")(0)).mkString(" ")
					val pair = List(Some(expLhs), Some(expRhs));
					val discourseIterpreter	= new PreparsedBoxerDiscourseInterpreter(pair, new PassthroughBoxerExpressionInterpreter());
					val List(lhsDrs, rhsDrs) = discourseIterpreter.batchInterpretMultisentence(List(List((expLhs)), List((expRhs))), Some(List("t", "h")), false, false)
					println (lhsDrs)
					println (rhsDrs)
					if (lhsDrs.isEmpty || rhsDrs.isEmpty)
						throw new RuntimeException ("Unparsable rule");
					//Some(id + "\t" + lhs + "\t" + rhs + "\t" + score + "\t" + RuleType.Implication)
					Some(lhsDrs.get.asInstanceOf[BoxerDrs], rhsDrs.get.asInstanceOf[BoxerDrs], score.toDouble, RuleType.Implication)
				}
			}.toList
			
		distRules
	}
  
  //process to match Barent rules. 
  def process(s:String):String = {
    val sLowerCase = s;
    val tokens = sLowerCase.split(" "); //It is enough to use "split" because the string is already tokenized
    val filteredTokens = tokens.filterNot(Rules.tokensToRemoveFromRules.contains(_))
    //the # are to avoid matching part of a token
    val stringToCompare = "#" + filteredTokens.mkString("#")+"#";
    return stringToCompare; 
  }
  
  
  
  def getRulesOld(): List[String] = {
    // Search phrases in Text
    val txtPhrases = Sts.luceneDistPhrases.query(Sts.text + " " + Sts.textLemma)
      .filter { phrase =>

        val Array(id, content) = phrase.split("\t")
        val str = " " + content + " "

        val simpleTxt = (" " + Sts.text.split(" ") + " ")
        val simpleLemTxt = (" " + Sts.textLemma.split(" ") + " ")

        val cond = simpleTxt.contains(str) || simpleLemTxt.contains(str)

        val extraStr = " some" + str
        val extraCond = !simpleTxt.contains(extraStr) && !simpleLemTxt.contains(extraStr)

        cond && extraCond
      }.toList

    // Search phrases in Hypothesis
    val hypPhrases = Sts.luceneDistPhrases.query(Sts.hypothesis + " " + Sts.hypothesisLemma)
      .filter { phrase =>

        val Array(id, content) = phrase.split("\t")
        val str = " " + content + " "

        val simpleHyp = (" " + Sts.hypothesis.split(" ") + " ")
        val simpleLemHyp = (" " + Sts.hypothesisLemma.split(" ") + " ")

        val cond = simpleHyp.contains(str) || simpleLemHyp.contains(str)

        val extraStr = " some" + str
        val extraCond = !simpleHyp.contains(extraStr) && !simpleLemHyp.contains(extraStr)

        cond && extraCond
      }.toList

    // Compute similaritis between phrases and generate corresponding rules in the following format: 
    // <id> TAB <text_phrase> TAB <hypo_phrase> TAB <sim_score>
    val distRules = generatePairs(txtPhrases, hypPhrases);
    LOG.trace("Distributional rules: ");
    distRules.foreach(rule => LOG.trace(rule))
    return distRules;
  }

  private def generatePairs(txtPhrases: List[String], hypPhrases: List[String]): List[String] =
  {
      //phrase vectors
	  if (Sts.opts.phraseVecsFile == "")
        return List[String]();

      //val phraseVecs = readLines(filename, "ISO-8859-1").toList
      val phraseVecs = readLines(Sts.opts.phraseVecsFile).toList
      var distRules = List[String]()

      val txtPhraseVecs = txtPhrases.map { txtPhrase =>
        val Array(id, content) = txtPhrase.split("\t")
        phraseVecs(id.toInt - 1).split("\t")
          .drop(1)
          .map(_.toDouble)
          .toList
      }
      LOG.trace("Found Text Phrases: ");
      txtPhrases.foreach(vec => LOG.trace(vec))

      val hypPhraseVecs = hypPhrases.map { hypPhrase =>
        val Array(id, content) = hypPhrase.split("\t")
        phraseVecs(id.toInt - 1).split("\t")
          .drop(1)
          .map(_.toDouble)
          .toList
      }

      LOG.trace("Found Hypothesis Phrases: ");
      hypPhrases.foreach(vec => LOG.trace(vec))

      txtPhrases.zip(txtPhraseVecs).foreach {
        case (txtPhrase, txtPhraseVec) =>
          val Array(txtId, txtContent) = txtPhrase.split("\t")

          hypPhrases.zip(hypPhraseVecs).foreach {
            case (hypPhrase, hypPhraseVec) =>
              val Array(hypId, hypContent) = hypPhrase.split("\t")
              val newId = txtId + "_" + hypId
              val simScore = cosine(txtPhraseVec, hypPhraseVec)
              val rule = newId + "\t" + txtContent + "\t" + hypContent + "\t" + simScore
              distRules :+= rule
          }
      }

      distRules
    }

  private def cosine(vec1: List[Double], vec2: List[Double]): Double =
  {
      val numer = vec1.zip(vec2).sumBy {
        case (x, y) =>
          val v = x * y
          if (v >= 0) v
          else 0.0
      }
      val denom1 = math.sqrt(vec1.sumBy { x => x * x })
      val denom2 = math.sqrt(vec2.sumBy { y => y * y })
      val denom = denom1 * denom2

      if (denom > 0) numer / denom
      else 0
  }
}

object DistributionalRules{
  
}
