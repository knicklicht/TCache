-----------------------------------------------------------------------------
--
-- Module      :  Memoization
-- Copyright   :  Alberto GOmez Corona
-- License     :  BSD3
--
-- Maintainer  :  agocorona@gmail.com
-- Stability   :  Experimental
-- Portability :  Non portable (uses stablenames)
--
-- |
--
-----------------------------------------------------------------------------
{-# LANGUAGE  DeriveDataTypeable
            , ExistentialQuantification
            , FlexibleInstances
            , TypeSynonymInstances  #-}
module Data.TCache.Memoization (cachedByKey,cachedp,addrStr,addrHash,Executable(..))

where
import Data.Typeable
import Data.TCache
import Data.TCache.Defs(Indexable(..))
import System.Mem.StableName
import System.IO.Unsafe
import System.Time
import Data.Maybe(fromJust)
import Control.Monad.Trans
import Control.Monad.Identity

import Debug.Trace
(!>)= flip trace

data Cached a b= forall m.Executable m => Cached a (a -> m b) b Integer deriving Typeable




-- | return a string identifier for any object
addrStr :: MonadIO m => a -> m String
addrStr x = addrHash x >>= return . show

-- | return a hash of an object
addrHash :: MonadIO m => a -> m Int

{-# NOINLINE addrHash #-}
addrHash x=  liftIO $ do
       st <- makeStableName $! x
       return $ hashStableName st


-- | to execute a monad for the purpose of memoizing its result
class Executable m where
  execute:: m a -> a

instance Executable IO where
  execute= unsafePerformIO

instance Executable Identity where
  execute (Identity x)= x

instance MonadIO Identity where
  liftIO= Identity . unsafePerformIO

instance  (Indexable a, Typeable a) => IResource (Cached a  b) where
  keyResource ch@(Cached a  f _ _)= "cached"++key a -- ++ unsafePerformIO (addrStr f )  --`debug` ("k="++ show k)

  writeResource _= return ()
  delResource _= return ()
  readResourceByKey= error "access By Indexable is undefined for chached objects"

  readResource (Cached a f _ _)=do
   TOD tnow _ <- getClockTime
   let b = execute $ f a
   return . Just $ Cached a f b tnow

instance Indexable String where
   key= id

-- | memoize the result of a computation for a certain time. This is useful for  caching  costly data
-- such  web pages composed on the fly.
--
-- time == 0 means infinite
cached ::  (Indexable a, Typeable a, Typeable b, Executable m,MonadIO m) => Int -> (a -> m b) -> a  -> m b
cached time  f a=  do
   cho@(Cached _ _ b t)  <- liftIO $ getResource ( (Cached a f undefined undefined )) >>= return . fromJust
   case time of
     0 -> return b
     _ -> do
           TOD tnow _ <- liftIO $ getClockTime
           if time /=0 && tnow - t > fromIntegral time
                      then do
                          liftIO $ deleteResource cho
                          cached time f a
                      else  return b

-- | Memoize the result of a computation for a certain time. A string 'key' is used to index the result
--
-- The Int parameter is the timeout, in second after the last evaluation, after which the cached value will be discarded and the expression will be evaluated again if demanded
-- . Time == 0 means no timeout
cachedByKey :: (Typeable a, Executable m,MonadIO m) => String -> Int ->  m a -> m a
cachedByKey key time  f = cached  time (\_ -> f) key


-- | a pure version of cached
cachedp :: (Indexable a,Typeable a,Typeable b) => (a ->b) -> a -> b
cachedp f k = execute $ cached  0 (\x -> Identity $ f x) k

--testmemo= do
--   let f x = "hi"++x  !> "exec1"
--   let f1 x= "h0"++x  !> "exec2"
--   let beacon=1
--   let beacon2=2
--   print $ cachedp f (addrStr "sfs")
--   print $ cachedp f (addrStr "sds")
--   print $ cachedp f1 (addrStr "ssdfddd")
--   print $ cachedp f1 (addrStr "sss")


